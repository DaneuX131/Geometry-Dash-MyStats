import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const GdPushApp());
}

class GdPushApp extends StatelessWidget {
  const GdPushApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GD Push',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0C0D12),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFFF4081),
          surface: Color(0xFF151720),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class RunRecord {
  final int start; // 0..100
  final int end; // 0..100
  final String label;

  RunRecord({
    required this.start,
    required this.end,
    String? label,
  }) : label = label ?? '$start–$end%';

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'label': label,
      };

  factory RunRecord.fromJson(Map<String, dynamic> json) {
    final s = (json['start'] as int? ?? 0).clamp(0, 100);
    final e = (json['end'] as int? ?? 0).clamp(0, 100);
    return RunRecord(
      start: s < e ? s : e,
      end: s < e ? e : s,
      label: json['label'] as String? ?? '$s–$e%',
    );
  }
}

class DemonLevel {
  final String id;
  String name;
  String creator;
  String source; // 'Pointercrate', 'Demonlist.org', 'Custom'
  int? rank; // Позиция в топе (например 14, 142, 620 или null)
  String difficulty;
  int bestFromZero; // 0..100
  List<RunRecord> runs;
  String notes;

  DemonLevel({
    required this.id,
    required this.name,
    this.creator = '',
    this.source = 'Pointercrate',
    this.rank,
    this.difficulty = 'Extreme Demon',
    this.bestFromZero = 0,
    List<RunRecord>? runs,
    this.notes = '',
  }) : runs = runs ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'creator': creator,
        'source': source,
        'rank': rank,
        'difficulty': difficulty,
        'bestFromZero': bestFromZero,
        'runs': runs.map((r) => r.toJson()).toList(),
        'notes': notes,
      };

  factory DemonLevel.fromJson(Map<String, dynamic> json) {
    final rawRuns = (json['runs'] as List<dynamic>? ?? [])
        .map((e) => RunRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return DemonLevel(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'Unnamed',
      creator: json['creator'] as String? ?? '',
      source: json['source'] as String? ?? 'Pointercrate',
      rank: json['rank'] as int?,
      difficulty: json['difficulty'] as String? ?? 'Extreme Demon',
      bestFromZero: (json['bestFromZero'] as int? ?? 0).clamp(0, 100),
      runs: rawRuns,
      notes: json['notes'] as String? ?? '',
    );
  }
}

class LevelAnalysis {
  final int totalCoveragePct; // Сколько % уровня покрыто ранами/0-X
  final int bestEndPct; // Самый дальний достигнутый конец (например 100 или 88)
  final List<String> gaps; // Незакрытые дыры вроде ["25–38%", "61–74%"]
  final String verdictTitle;
  final String verdictBody;
  final Color accentColor;
  final IconData icon;

  LevelAnalysis({
    required this.totalCoveragePct,
    required this.bestEndPct,
    required this.gaps,
    required this.verdictTitle,
    required this.verdictBody,
    required this.accentColor,
    required this.icon,
  });
}

LevelAnalysis analyzeLevel(DemonLevel level) {
  final List<List<int>> intervals = [];

  if (level.bestFromZero > 0) {
    intervals.add([0, level.bestFromZero.clamp(0, 100)]);
  }

  int bestEnd = level.bestFromZero.clamp(0, 100);
  for (final r in level.runs) {
    final a = r.start.clamp(0, 100);
    final b = r.end.clamp(0, 100);
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    if (hi > lo) {
      intervals.add([lo, hi]);
    }
    if (hi > bestEnd) {
      bestEnd = hi;
    }
  }

  // Объединяем пересекающиеся интервалы
  intervals.sort((a, b) => a[0] != b[0] ? a[0].compareTo(b[0]) : a[1].compareTo(b[1]));
  final List<List<int>> merged = [];
  for (final seg in intervals) {
    if (merged.isEmpty || seg[0] > merged.last[1]) {
      merged.add([seg[0], seg[1]]);
    } else if (seg[1] > merged.last[1]) {
      merged.last[1] = seg[1];
    }
  }

  int covered = 0;
  for (final seg in merged) {
    covered += (seg[1] - seg[0]);
  }
  covered = covered.clamp(0, 100);

  // Находим крупные дыры (>= 8%) между покрытыми сегментами
  final List<String> gaps = [];
  int cursor = 0;
  for (final seg in merged) {
    if (seg[0] > cursor && (seg[0] - cursor) >= 8) {
      gaps.add('$cursor–${seg[0]}%');
    }
    if (seg[1] > cursor) cursor = seg[1];
  }
  if (100 > cursor && (100 - cursor) >= 8) {
    gaps.add('$cursor–100%');
  }

  // Порог готовности к пушу с 0% зависит от позиции в топе
  int zeroThreshold = 60;
  int endThreshold = 85;
  if (level.rank != null) {
    if (level.rank! <= 75) {
      zeroThreshold = 72;
      endThreshold = 90;
    } else if (level.rank! <= 150) {
      zeroThreshold = 66;
      endThreshold = 88;
    }
  }

  if (level.bestFromZero >= 100) {
    return LevelAnalysis(
      totalCoveragePct: 100,
      bestEndPct: 100,
      gaps: const [],
      verdictTitle: 'Пройден на 100%',
      verdictBody: 'Уровень закрыт! Можно гонять с 0% ради консистентности или перепрохода.',
      accentColor: const Color(0xFF00E676),
      icon: Icons.emoji_events_rounded,
    );
  }

  final hasSolidEnd = bestEnd >= endThreshold;
  final gapText = gaps.isEmpty ? 'критических дыр нет' : 'дыры: ${gaps.take(2).join(', ')}';

  if (level.bestFromZero >= zeroThreshold && hasSolidEnd && gaps.length <= 1) {
    return LevelAnalysis(
      totalCoveragePct: covered,
      bestEndPct: bestEnd,
      gaps: gaps,
      verdictTitle: 'Пора идти с 0%',
      verdictBody:
          'Лучший с 0% уже ${level.bestFromZero}%, концовка закрыта до $bestEnd% ($gapText). Смело делай основной фокус на попытках с нуля.',
      accentColor: const Color(0xFF00E676),
      icon: Icons.local_fire_department_rounded,
    );
  }

  if (level.bestFromZero >= (zeroThreshold - 18) || (hasSolidEnd && covered >= 65)) {
    return LevelAnalysis(
      totalCoveragePct: covered,
      bestEndPct: bestEnd,
      gaps: gaps,
      verdictTitle: 'Чередуй 0% и раны',
      verdictBody: hasSolidEnd
          ? 'Концовка есть ($bestEnd%), покрытие $covered% ($gapText). Делай сеты с 0% и добивай провалы.'
          : 'База с 0% есть (${level.bestFromZero}%), но концовка пока только до $bestEnd%. Подтяни финал, чтобы не слиться в конце.',
      accentColor: const Color(0xFFFFAB00),
      icon: Icons.swap_horiz_rounded,
    );
  }

  return LevelAnalysis(
    totalCoveragePct: covered,
    bestEndPct: bestEnd,
    gaps: gaps,
    verdictTitle: 'Сначала раны и практика',
    verdictBody:
        'Лучший с 0% пока ${level.bestFromZero}%, покрытие $covered% ($gapText). Выгоднее сначала собрать раны и концовку.',
    accentColor: const Color(0xFFFF5252),
    icon: Icons.construction_rounded,
  );
}

class DemonSearchResult {
  final String name;
  final int? rank;
  final String creator;
  final String source;

  DemonSearchResult({
    required this.name,
    this.rank,
    this.creator = '',
    required this.source,
  });
}

class DemonlistService {
  static Future<List<DemonSearchResult>> searchDemons(
    String query,
    String source,
  ) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    if (source == 'Pointercrate') {
      return _searchPointercrate(q);
    } else if (source == 'Demonlist.org') {
      return _searchDemonlistOrg(q);
    }
    return [];
  }

  static Future<List<DemonSearchResult>> _searchPointercrate(String q) async {
    try {
      final uri = Uri.parse(
        'https://pointercrate.com/api/v2/demons/?name_contains=${Uri.encodeComponent(q)}&limit=15',
      );
      final res = await http.get(uri, headers: {
        'User-Agent': 'GDPushTracker/1.0',
      }).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          return data.map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            final publisher = map['publisher'] is Map
                ? (map['publisher']['name'] as String? ?? '')
                : '';
            return DemonSearchResult(
              name: map['name'] as String? ?? 'Unknown',
              rank: map['position'] as int?,
              creator: publisher,
              source: 'Pointercrate',
            );
          }).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  static Future<List<DemonSearchResult>> _searchDemonlistOrg(String q) async {
    try {
      // Пробуем стандартный API-эндпоинт demonlist.org, если доступен
      final uri = Uri.parse(
        'https://demonlist.org/api/v1/demons?limit=50',
      );
      final res = await http.get(uri, headers: {
        'User-Agent': 'GDPushTracker/1.0',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200 && res.body.trim().startsWith('{') || res.body.trim().startsWith('[')) {
        final decoded = jsonDecode(res.body);
        List rawList = [];
        if (decoded is List) {
          rawList = decoded;
        } else if (decoded is Map && decoded['data'] is List) {
          rawList = decoded['data'] as List;
        } else if (decoded is Map && decoded['demons'] is List) {
          rawList = decoded['demons'] as List;
        }

        final results = <DemonSearchResult>[];
        for (final item in rawList) {
          if (item is! Map) continue;
          final name = (item['name'] ?? item['title'] ?? '').toString();
          if (name.toLowerCase().contains(q)) {
            final posRaw = item['position'] ?? item['rank'] ?? item['placement'];
            final rank = posRaw is int
                ? posRaw
                : int.tryParse(posRaw?.toString() ?? '');
            final creator = (item['publisher'] ?? item['creator'] ?? item['verifier'] ?? '').toString();
            results.add(DemonSearchResult(
              name: name,
              rank: rank,
              creator: creator,
              source: 'Demonlist.org',
            ));
          }
        }
        if (results.isNotEmpty) return results.take(15).toList();
      }

      // Резервный лёгкий парсинг HTML страницы /classic
      final pageRes = await http.get(
        Uri.parse('https://demonlist.org/classic'),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(const Duration(seconds: 8));

      if (pageRes.statusCode == 200) {
        final text = pageRes.body.replaceAll(RegExp(r'<[^>]+>'), ' ');
        final lines = text
            .split(RegExp(r'\s{2,}|\n'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        final found = <DemonSearchResult>[];
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].toLowerCase().contains(q) && lines[i].length < 50) {
            int? parsedRank;
            if (i > 0) {
              final rankMatch = RegExp(r'#?(\d{1,4})').firstMatch(lines[i - 1]);
              if (rankMatch != null) {
                parsedRank = int.tryParse(rankMatch.group(1) ?? '');
              }
            }
            found.add(DemonSearchResult(
              name: lines[i],
              rank: parsedRank,
              source: 'Demonlist.org',
            ));
            if (found.length >= 10) break;
          }
        }
        return found;
      }
    } catch (_) {}
    return [];
  }
}

class StorageService {
  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/gd_levels_v1.json');
  }

  static Future<List<DemonLevel>> loadLevels() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        return [
          DemonLevel(
            id: 'demo_1',
            name: 'Cataclysm',
            creator: 'Ggb0y',
            source: 'Pointercrate',
            rank: 618,
            difficulty: 'Extreme Demon',
            bestFromZero: 24,
            runs: [
              RunRecord(start: 41, end: 100),
              RunRecord(start: 27, end: 76),
            ],
            notes: 'Начало волна, после дропа корабль.',
          ),
          DemonLevel(
            id: 'demo_2',
            name: 'Bloodbath',
            creator: 'Riot',
            source: 'Pointercrate',
            rank: 482,
            difficulty: 'Extreme Demon',
            bestFromZero: 19,
            runs: [
              RunRecord(start: 68, end: 100),
              RunRecord(start: 35, end: 72),
            ],
            notes: 'Концовка стабильнее, нужно добить середину.',
          ),
        ];
      }
      final content = await file.readAsString();
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .map((e) => DemonLevel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveLevels(List<DemonLevel> levels) async {
    try {
      final file = await _getFile();
      final encoded = jsonEncode(levels.map((e) => e.toJson()).toList());
      await file.writeAsString(encoded);
    } catch (_) {}
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<DemonLevel> _levels = [];
  bool _loading = true;
  String _filter = 'Все';

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final loaded = await StorageService.loadLevels();
    if (!mounted) return;
    setState(() {
      _levels = loaded;
      _loading = false;
    });
  }

  Future<void> _persist() async {
    await StorageService.saveLevels(_levels);
  }

  List<DemonLevel> get _filteredLevels {
    if (_filter == 'Готовы к 0%') {
      return _levels.where((l) {
        final a = analyzeLevel(l);
        return a.verdictTitle.contains('0%') || l.bestFromZero >= 100;
      }).toList();
    }
    if (_filter == 'В работе') {
      return _levels.where((l) => l.bestFromZero < 100).toList();
    }
    return _levels;
  }

  void _openLevelEditor({DemonLevel? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final creatorCtrl = TextEditingController(text: existing?.creator ?? '');
    final rankCtrl = TextEditingController(
      text: existing?.rank != null ? existing!.rank.toString() : '',
    );
    final diffCtrl = TextEditingController(
      text: existing?.difficulty ?? 'Extreme Demon',
    );
    final bestCtrl = TextEditingController(
      text: (existing?.bestFromZero ?? 0).toString(),
    );
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    String selectedSource = existing?.source ?? 'Pointercrate';
    List<DemonSearchResult> searchResults = [];
    bool searching = false;
    String searchHint = '';

    final diffPresets = [
      'Extreme Demon',
      'Insane Demon',
      'Hard Demon',
      'Medium Demon',
      'Easy Demon',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14161F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> runSearch() async {
              if (nameCtrl.text.trim().isEmpty) return;
              setModalState(() {
                searching = true;
                searchHint = '';
              });
              final res = await DemonlistService.searchDemons(
                nameCtrl.text,
                selectedSource,
              );
              setModalState(() {
                searching = false;
                searchResults = res;
                if (res.isEmpty) {
                  searchHint =
                      'Не найдено автоматически — впиши топ вручную ниже.';
                }
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          existing == null ? 'Добавить уровень' : 'Редактировать',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Источник списка',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'Pointercrate',
                          label: Text('Pointercrate', style: TextStyle(fontSize: 12)),
                        ),
                        ButtonSegment(
                          value: 'Demonlist.org',
                          label: Text('Demonlist.org', style: TextStyle(fontSize: 12)),
                        ),
                        ButtonSegment(
                          value: 'Custom',
                          label: Text('Свой', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                      selected: {selectedSource},
                      onSelectionChanged: (val) {
                        setModalState(() {
                          selectedSource = val.first;
                          searchResults = [];
                          searchHint = '';
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Название уровня',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        if (selectedSource != 'Custom') ...[
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            onPressed: searching ? null : runSearch,
                            icon: searching
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.search),
                            label: const Text('Найти'),
                          ),
                        ],
                      ],
                    ),
                    if (searchHint.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        searchHint,
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
                      ),
                    ],
                    if (searchResults.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 165),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0E1017),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: searchResults.length,
                          itemBuilder: (_, i) {
                            final item = searchResults[i];
                            return ListTile(
                              dense: true,
                              title: Text(item.name),
                              subtitle: Text(
                                item.creator.isNotEmpty ? item.creator : item.source,
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: Text(
                                item.rank != null ? '#${item.rank}' : '—',
                                style: const TextStyle(
                                  color: Color(0xFF00E5FF),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onTap: () {
                                setModalState(() {
                                  nameCtrl.text = item.name;
                                  if (item.creator.isNotEmpty) {
                                    creatorCtrl.text = item.creator;
                                  }
                                  if (item.rank != null) {
                                    rankCtrl.text = item.rank.toString();
                                  }
                                  searchResults = [];
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: rankCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Топ / Позиция (вручную)',
                              hintText: 'Например: 120',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: bestCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Лучший % с 0',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: diffCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Сложность',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: diffPresets
                          .map((d) => ActionChip(
                                label: Text(d, style: const TextStyle(fontSize: 11.5)),
                                onPressed: () =>
                                    setModalState(() => diffCtrl.text = d),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: creatorCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Создатель / Верификатор (необязательно)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Заметки по ранам и таймингам',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: () {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) return;

                          final rank = int.tryParse(rankCtrl.text.trim());
                          final best = (int.tryParse(bestCtrl.text.trim()) ?? 0)
                              .clamp(0, 100);
                          final diff = diffCtrl.text.trim().isEmpty
                              ? 'Demon'
                              : diffCtrl.text.trim();

                          setState(() {
                            if (existing == null) {
                              _levels.insert(
                                0,
                                DemonLevel(
                                  id: DateTime.now()
                                      .millisecondsSinceEpoch
                                      .toString(),
                                  name: name,
                                  creator: creatorCtrl.text.trim(),
                                  source: selectedSource,
                                  rank: rank,
                                  difficulty: diff,
                                  bestFromZero: best,
                                  notes: notesCtrl.text.trim(),
                                ),
                              );
                            } else {
                              existing.name = name;
                              existing.creator = creatorCtrl.text.trim();
                              existing.source = selectedSource;
                              existing.rank = rank;
                              existing.difficulty = diff;
                              existing.bestFromZero = best;
                              existing.notes = notesCtrl.text.trim();
                            }
                          });
                          _persist();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Сохранить уровень'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openAddRunDialog(DemonLevel level) {
    final startCtrl = TextEditingController();
    final endCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151720),
        title: Text('Новый ран — ${level.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Укажи границы рана (например 0 и 54, либо 52 и 100):',
              style: TextStyle(fontSize: 12.5, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: startCtrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'От %',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: endCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'До %',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final a = int.tryParse(startCtrl.text.trim());
              final b = int.tryParse(endCtrl.text.trim());
              if (a != null && b != null) {
                final lo = a.clamp(0, 100);
                final hi = b.clamp(0, 100);
                final s = lo < hi ? lo : hi;
                final e = lo < hi ? hi : lo;
                if (e > s) {
                  setState(() {
                    if (s == 0 && e > level.bestFromZero) {
                      level.bestFromZero = e;
                    }
                    level.runs.insert(0, RunRecord(start: s, end: e));
                  });
                  _persist();
                }
              }
              Navigator.pop(ctx);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredLevels;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          children: [
            Text(
              'GD PUSH',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 18,
              ),
            ),
            Text(
              'Раны • Демонлисты • Пуш с 0%',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openLevelEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Уровень'),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: ['Все', 'В работе', 'Готовы к 0%'].map((tab) {
                final selected = _filter == tab;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(tab),
                    selected: selected,
                    onSelected: (_) => setState(() => _filter = tab),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? const Center(
                        child: Text(
                          'Пока пусто. Нажми «+ Уровень» и добавь свой демон.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
                        itemCount: list.length,
                        itemBuilder: (context, idx) {
                          final lvl = list[idx];
                          final analysis = analyzeLevel(lvl);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: const Color(0xFF151720),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  lvl.name,
                                                  style: const TextStyle(
                                                    fontSize: 19,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                              if (lvl.rank != null) ...[
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF00E5FF)
                                                        .withValues(alpha: 0.14),
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    '#${lvl.rank}',
                                                    style: const TextStyle(
                                                      color: Color(0xFF00E5FF),
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            [
                                              lvl.difficulty,
                                              if (lvl.creator.isNotEmpty) lvl.creator,
                                              lvl.source,
                                            ].join(' • '),
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline),
                                      tooltip: 'Добавить ран',
                                      onPressed: () => _openAddRunDialog(lvl),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 20),
                                      onPressed: () =>
                                          _openLevelEditor(existing: lvl),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 20,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () {
                                        setState(() => _levels.remove(lvl));
                                        _persist();
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'С 0%: ${lvl.bestFromZero}%',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      'Покрытие: ${analysis.totalCoveragePct}% • Финал: ${analysis.bestEndPct}%',
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: analysis.totalCoveragePct / 100,
                                    minHeight: 8,
                                    backgroundColor: Colors.white10,
                                    color: analysis.accentColor,
                                  ),
                                ),
                                if (lvl.runs.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: lvl.runs
                                        .map((r) => Chip(
                                              label: Text(
                                                r.label,
                                                style: const TextStyle(fontSize: 12),
                                              ),
                                              visualDensity: VisualDensity.compact,
                                              onDeleted: () {
                                                setState(() => lvl.runs.remove(r));
                                                _persist();
                                              },
                                            ))
                                        .toList(),
                                  ),
                                ],
                                if (lvl.notes.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    lvl.notes,
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: analysis.accentColor
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: analysis.accentColor
                                          .withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        analysis.icon,
                                        color: analysis.accentColor,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              analysis.verdictTitle,
                                              style: TextStyle(
                                                color: analysis.accentColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              analysis.verdictBody,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12.5,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

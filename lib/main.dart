import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChildrenWordsApp());
}

const _green = Color(0xFF45B36B);
const _blue = Color(0xFF4AA3DF);
const _orange = Color(0xFFFFB84D);
const _cream = Color(0xFFFFFBF0);
const _ink = Color(0xFF25313B);

enum LearnFilter { all, learning, learned }

class ChildrenWordsApp extends StatelessWidget {
  const ChildrenWordsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '生字小本本',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _cream,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _green,
          primary: _green,
          secondary: _blue,
          tertiary: _orange,
          surface: Colors.white,
        ),
        fontFamily: 'sans',
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: _cream,
          foregroundColor: _ink,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: _ink,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
      home: const WordListPage(),
    );
  }
}

class WordEntry {
  WordEntry({
    required this.id,
    required this.character,
    required this.glyphImageUrl,
    required this.strokeGifUrl,
    required this.primaryPinyin,
    required this.note,
    required this.isLearned,
    required this.createdAt,
    required this.updatedAt,
    required this.pronunciations,
  });

  final String id;
  final String character;
  final String glyphImageUrl;
  final String strokeGifUrl;
  final String primaryPinyin;
  final String note;
  final bool isLearned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Pronunciation> pronunciations;

  String get pinyinText {
    final values = pronunciations
        .map((p) => p.pinyin)
        .where((p) => p.isNotEmpty);
    return values.isEmpty ? primaryPinyin : values.join(' ');
  }

  String get previewExplanation {
    final text = pronunciations
        .map((p) => p.basicExplanation)
        .firstWhere((value) => value.trim().isNotEmpty, orElse: () => note);
    return text.trim();
  }

  WordEntry copyWith({
    String? id,
    String? character,
    String? glyphImageUrl,
    String? strokeGifUrl,
    String? primaryPinyin,
    String? note,
    bool? isLearned,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Pronunciation>? pronunciations,
  }) {
    return WordEntry(
      id: id ?? this.id,
      character: character ?? this.character,
      glyphImageUrl: glyphImageUrl ?? this.glyphImageUrl,
      strokeGifUrl: strokeGifUrl ?? this.strokeGifUrl,
      primaryPinyin: primaryPinyin ?? this.primaryPinyin,
      note: note ?? this.note,
      isLearned: isLearned ?? this.isLearned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pronunciations: pronunciations ?? this.pronunciations,
    );
  }
}

class Pronunciation {
  Pronunciation({
    required this.id,
    required this.wordId,
    required this.pinyin,
    required this.zhuyin,
    required this.basicExplanation,
    required this.sortOrder,
  });

  final String id;
  final String wordId;
  final String pinyin;
  final String zhuyin;
  final String basicExplanation;
  final int sortOrder;

  Pronunciation copyWith({
    String? id,
    String? wordId,
    String? pinyin,
    String? zhuyin,
    String? basicExplanation,
    int? sortOrder,
  }) {
    return Pronunciation(
      id: id ?? this.id,
      wordId: wordId ?? this.wordId,
      pinyin: pinyin ?? this.pinyin,
      zhuyin: zhuyin ?? this.zhuyin,
      basicExplanation: basicExplanation ?? this.basicExplanation,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

class ZdicResult {
  ZdicResult({
    required this.character,
    required this.glyphImageUrl,
    required this.strokeGifUrl,
    required this.pronunciations,
  });

  final String character;
  final String glyphImageUrl;
  final String strokeGifUrl;
  final List<PronunciationDraft> pronunciations;
}

class PronunciationDraft {
  PronunciationDraft({
    required this.pinyin,
    required this.zhuyin,
    required this.basicExplanation,
  });

  final String pinyin;
  final String zhuyin;
  final String basicExplanation;
}

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    final dbPath = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dbPath, 'children_words.db'),
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE words (
            id TEXT PRIMARY KEY,
            character TEXT NOT NULL UNIQUE,
            glyph_image_url TEXT NOT NULL DEFAULT '',
            stroke_gif_url TEXT NOT NULL DEFAULT '',
            primary_pinyin TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            is_learned INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_words_character ON words(character)',
        );
        await db.execute(
          'CREATE INDEX idx_words_is_learned ON words(is_learned)',
        );
        await db.execute(
          'CREATE INDEX idx_words_created_at ON words(created_at)',
        );
        await db.execute(
          'CREATE INDEX idx_words_primary_pinyin ON words(primary_pinyin)',
        );
        await db.execute('''
          CREATE TABLE pronunciations (
            id TEXT PRIMARY KEY,
            word_id TEXT NOT NULL,
            pinyin TEXT NOT NULL DEFAULT '',
            zhuyin TEXT NOT NULL DEFAULT '',
            basic_explanation TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(word_id) REFERENCES words(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_pronunciations_word_id ON pronunciations(word_id)',
        );
        await db.execute(
          'CREATE INDEX idx_pronunciations_pinyin ON pronunciations(pinyin)',
        );
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.insert('settings', {
          'key': 'hide_learned_words',
          'value': 'false',
          'updated_at': DateTime.now().toIso8601String(),
        });
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE words ADD COLUMN stroke_gif_url TEXT NOT NULL DEFAULT ''",
          );
        }
      },
    );
    _database = db;
    return db;
  }

  Future<bool> getHideLearnedWords() async {
    final db = await database;
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['hide_learned_words'],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['value'] == 'true';
  }

  Future<void> setHideLearnedWords(bool value) async {
    final db = await database;
    await db.insert('settings', {
      'key': 'hide_learned_words',
      'value': value ? 'true' : 'false',
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<WordEntry>> listWords({
    LearnFilter filter = LearnFilter.all,
    String query = '',
    bool hideLearned = false,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (hideLearned) {
      where.add('is_learned = 0');
    } else if (filter == LearnFilter.learning) {
      where.add('is_learned = 0');
    } else if (filter == LearnFilter.learned) {
      where.add('is_learned = 1');
    }
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isNotEmpty) {
      final like = '%$normalizedQuery%';
      where.add(
        '(character LIKE ? OR primary_pinyin LIKE ? OR '
        'lower(primary_pinyin) LIKE ?)',
      );
      args.addAll([like, like, like]);
    }
    final wordRows = await db.query(
      'words',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy:
          'primary_pinyin COLLATE NOCASE ASC, character ASC, created_at ASC',
    );
    final words = <WordEntry>[];
    for (final row in wordRows) {
      words.add(await _entryFromRow(db, row));
    }
    if (normalizedQuery.isEmpty) return words;
    return words.where((word) {
      final initials = pinyinInitials(word.pinyinText);
      return word.character.contains(normalizedQuery) ||
          word.pinyinText.toLowerCase().contains(normalizedQuery) ||
          initials.contains(normalizedQuery);
    }).toList();
  }

  Future<WordEntry?> getWord(String id) async {
    final db = await database;
    final rows = await db.query('words', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _entryFromRow(db, rows.first);
  }

  Future<WordEntry?> findByCharacter(String character) async {
    final db = await database;
    final rows = await db.query(
      'words',
      where: 'character = ?',
      whereArgs: [character],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _entryFromRow(db, rows.first);
  }

  Future<void> upsertWord(WordEntry word) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('words', {
        'id': word.id,
        'character': word.character,
        'glyph_image_url': word.glyphImageUrl,
        'stroke_gif_url': word.strokeGifUrl,
        'primary_pinyin': word.primaryPinyin,
        'note': word.note,
        'is_learned': word.isLearned ? 1 : 0,
        'created_at': word.createdAt.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete(
        'pronunciations',
        where: 'word_id = ?',
        whereArgs: [word.id],
      );
      for (var i = 0; i < word.pronunciations.length; i++) {
        final item = word.pronunciations[i];
        await txn.insert('pronunciations', {
          'id': item.id.isEmpty ? makeId('py') : item.id,
          'word_id': word.id,
          'pinyin': item.pinyin,
          'zhuyin': item.zhuyin,
          'basic_explanation': item.basicExplanation,
          'sort_order': i,
        });
      }
    });
  }

  Future<void> updateLearned(String id, bool value) async {
    final db = await database;
    await db.update(
      'words',
      {
        'is_learned': value ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteWord(String id) async {
    final db = await database;
    await db.delete('words', where: 'id = ?', whereArgs: [id]);
  }

  Future<WordEntry> _entryFromRow(
    DatabaseExecutor db,
    Map<String, Object?> row,
  ) async {
    final id = row['id'] as String;
    final pronunciationRows = await db.query(
      'pronunciations',
      where: 'word_id = ?',
      whereArgs: [id],
      orderBy: 'sort_order ASC',
    );
    return WordEntry(
      id: id,
      character: row['character'] as String,
      glyphImageUrl: row['glyph_image_url'] as String,
      strokeGifUrl: (row['stroke_gif_url'] as String?) ?? '',
      primaryPinyin: row['primary_pinyin'] as String,
      note: row['note'] as String,
      isLearned: (row['is_learned'] as int) == 1,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      pronunciations: pronunciationRows
          .map(
            (p) => Pronunciation(
              id: p['id'] as String,
              wordId: p['word_id'] as String,
              pinyin: p['pinyin'] as String,
              zhuyin: p['zhuyin'] as String,
              basicExplanation: p['basic_explanation'] as String,
              sortOrder: p['sort_order'] as int,
            ),
          )
          .toList(),
    );
  }
}

class ZdicService {
  Future<ZdicResult> fetch(String character) async {
    final uri = Uri.https('zdic.net', '/hans/$character');
    final response = await http.get(
      uri,
      headers: {'User-Agent': 'children-words-app/1.0'},
    );
    if (response.statusCode != 200) {
      throw Exception('查询失败：HTTP ${response.statusCode}');
    }
    final source = utf8.decode(response.bodyBytes);
    final document = html_parser.parse(source);
    final glyphElement =
        document.querySelector('#glyph-img') ??
        document.querySelector('.char-glyph__img');
    final glyph = _absoluteUrl(glyphElement?.attributes['src'] ?? '');
    final strokeGif = _absoluteUrl(
      glyphElement?.attributes['data-gif'] ?? _strokeGifFromGlyph(glyph),
    );
    final pinyins = document
        .querySelectorAll('.meta-pinyin')
        .map(
          (e) => cleanText(
            e.nodes.where((n) => n.nodeType == 3).map((n) => n.text).join(' '),
          ),
        )
        .expand((text) => text.split(RegExp(r'\s+')))
        .map((text) => text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
    final zhuyins = document
        .querySelectorAll('.meta-zhuyin')
        .map(
          (e) => cleanText(
            e.nodes.where((n) => n.nodeType == 3).map((n) => n.text).join(' '),
          ),
        )
        .expand((text) => text.split(RegExp(r'\s+')))
        .map((text) => text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
    final basic = cleanText(document.querySelector('#jbjs')?.text ?? '');
    final drafts = _parseBasicExplanation(character, basic, pinyins, zhuyins);
    return ZdicResult(
      character: character,
      glyphImageUrl: glyph,
      strokeGifUrl: strokeGif,
      pronunciations: drafts.isEmpty
          ? [
              PronunciationDraft(
                pinyin: pinyins.isEmpty ? '' : pinyins.first,
                zhuyin: zhuyins.isEmpty ? '' : zhuyins.first,
                basicExplanation: '',
              ),
            ]
          : drafts,
    );
  }

  List<PronunciationDraft> _parseBasicExplanation(
    String character,
    String text,
    List<String> pinyins,
    List<String> zhuyins,
  ) {
    var cleaned = text
        .replaceAll('基本解释', '')
        .replaceAll('◎', '')
        .replaceAll('汉典', '')
        .replaceAll('zdic.net', '')
        .trim();
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return [];

    final marker = RegExp(
      '●\\s*$character\\s+([^\\s，,。；;]+)(?:\\s+([^\\s，,。；;]+))?',
    );
    final matches = marker.allMatches(cleaned).toList();
    if (matches.isEmpty) {
      return [
        PronunciationDraft(
          pinyin: pinyins.isEmpty ? '' : pinyins.first,
          zhuyin: zhuyins.isEmpty ? '' : zhuyins.first,
          basicExplanation: _trimExplanation(cleaned),
        ),
      ];
    }

    final result = <PronunciationDraft>[];
    for (var i = 0; i < matches.length; i++) {
      final current = matches[i];
      final nextStart = i + 1 < matches.length
          ? matches[i + 1].start
          : cleaned.length;
      final body = cleaned.substring(current.end, nextStart);
      final pinyin = current.group(1)?.trim() ?? '';
      final zhuyin =
          current.group(2)?.trim() ?? (i < zhuyins.length ? zhuyins[i] : '');
      result.add(
        PronunciationDraft(
          pinyin: pinyin,
          zhuyin: zhuyin,
          basicExplanation: _trimExplanation(body),
        ),
      );
    }
    return result;
  }

  String _trimExplanation(String text) {
    return cleanText(
      text
          .replaceAll(RegExp(r'详见.*'), '')
          .replaceAll(RegExp(r'英语.*'), '')
          .replaceAll(RegExp(r'德语.*'), '')
          .replaceAll(RegExp(r'法语.*'), ''),
    );
  }

  String _absoluteUrl(String url) {
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) return 'https://zdic.net$url';
    return url;
  }

  String _strokeGifFromGlyph(String glyphUrl) {
    final match = RegExp(r'/kai/cn/([0-9A-Fa-f]+)\.svg').firstMatch(glyphUrl);
    if (match == null) return '';
    return '//img.zdic.net/kai/jbh/${match.group(1)!.toUpperCase()}.gif';
  }
}

class WordListPage extends StatefulWidget {
  const WordListPage({super.key});

  @override
  State<WordListPage> createState() => _WordListPageState();
}

class _WordListPageState extends State<WordListPage> {
  LearnFilter _filter = LearnFilter.all;
  String _query = '';
  bool _hideLearned = false;
  late Future<List<WordEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<WordEntry>> _load() async {
    _hideLearned = await AppDatabase.instance.getHideLearnedWords();
    return AppDatabase.instance.listWords(
      filter: _filter,
      query: _query,
      hideLearned: _hideLearned,
    );
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _openEditor([WordEntry? word]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => WordEditPage(existing: word)),
    );
    if (changed == true) _refresh();
  }

  Future<void> _openSettings() async {
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const SettingsPage()));
    if (changed == true) _refresh();
  }

  Future<void> _openDetail(WordEntry word, List<WordEntry> words) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => WordDetailPage(initialWordId: word.id)),
    );
    if (changed == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('生字小本本'),
        actions: [
          IconButton(
            tooltip: '配置',
            onPressed: _openSettings,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      hintText: '输入生字或拼音首字母',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (value) {
                      _query = value;
                      _refresh();
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<LearnFilter>(
                          segments: const [
                            ButtonSegment(
                              value: LearnFilter.all,
                              label: Text('全部'),
                            ),
                            ButtonSegment(
                              value: LearnFilter.learning,
                              label: Text('未会'),
                            ),
                            ButtonSegment(
                              value: LearnFilter.learned,
                              label: Text('已会'),
                            ),
                          ],
                          selected: {_filter},
                          onSelectionChanged: _hideLearned
                              ? null
                              : (values) {
                                  _filter = values.first;
                                  _refresh();
                                },
                        ),
                      ),
                    ],
                  ),
                  if (_hideLearned)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.visibility_off_rounded,
                            size: 16,
                            color: _green,
                          ),
                          SizedBox(width: 6),
                          Text('已在配置中隐藏已学会生字'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<WordEntry>>(
                future: _future,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final words = snapshot.data!;
                  if (words.isEmpty) {
                    return EmptyWords(onAdd: () => _openEditor());
                  }
                  return Stack(
                    children: [
                      ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 34, 96),
                        itemCount: words.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final word = words[index];
                          return WordCard(
                            word: word,
                            onTap: () => _openDetail(word, words),
                            onChanged: (value) async {
                              await AppDatabase.instance.updateLearned(
                                word.id,
                                value,
                              );
                              _refresh();
                            },
                          );
                        },
                      ),
                      Positioned(
                        right: 6,
                        top: 0,
                        bottom: 24,
                        child: AlphabetRail(words: words),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('添加生字'),
      ),
    );
  }
}

class WordCard extends StatelessWidget {
  const WordCard({
    required this.word,
    required this.onTap,
    required this.onChanged,
    super.key,
  });

  final WordEntry word;
  final VoidCallback onTap;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              GlyphBox(word: word, size: 66),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            word.pinyinText.isEmpty ? '待补充拼音' : word.pinyinText,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: _blue,
                            ),
                          ),
                        ),
                        LearnedChip(isLearned: word.isLearned),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      word.previewExplanation.isEmpty
                          ? '点开看看，补充解释和备注'
                          : word.previewExplanation,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _ink.withValues(alpha: 0.72),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(value: word.isLearned, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class AlphabetRail extends StatelessWidget {
  const AlphabetRail({required this.words, super.key});

  final List<WordEntry> words;

  @override
  Widget build(BuildContext context) {
    final letters =
        words
            .map((w) => pinyinInitials(w.primaryPinyin).toUpperCase())
            .where((s) => s.isNotEmpty)
            .map((s) => s[0])
            .toSet()
            .toList()
          ..sort();
    return Container(
      width: 22,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: letters
            .map(
              (letter) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  letter,
                  style: const TextStyle(
                    fontSize: 10,
                    color: _blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class EmptyWords extends StatelessWidget {
  const EmptyWords({required this.onAdd, super.key});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(54),
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                size: 58,
                color: _orange,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '还没有生字',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              '添加第一个生字，拼音和解释会自动帮你查好。',
              textAlign: TextAlign.center,
              style: TextStyle(color: _ink.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加第一个生字'),
            ),
          ],
        ),
      ),
    );
  }
}

class WordEditPage extends StatefulWidget {
  const WordEditPage({super.key, this.existing});

  final WordEntry? existing;

  @override
  State<WordEditPage> createState() => _WordEditPageState();
}

class _WordEditPageState extends State<WordEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _characterController = TextEditingController();
  final _noteController = TextEditingController();
  final _zdic = ZdicService();
  final List<_PronunciationControllers> _pronunciationControllers = [];
  String _glyphImageUrl = '';
  bool _isLearned = false;
  bool _loading = false;
  String? _message;
  Timer? _debounce;
  String _strokeGifUrl = '';

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final word = widget.existing;
    if (word != null) {
      _characterController.text = word.character;
      _noteController.text = word.note;
      _glyphImageUrl = word.glyphImageUrl;
      _strokeGifUrl = word.strokeGifUrl;
      _isLearned = word.isLearned;
      for (final pronunciation in word.pronunciations) {
        _pronunciationControllers.add(
          _PronunciationControllers.fromPronunciation(pronunciation),
        );
      }
    }
    if (_pronunciationControllers.isEmpty) _addPronunciation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _characterController.dispose();
    _noteController.dispose();
    for (final controller in _pronunciationControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addPronunciation([PronunciationDraft? draft]) {
    _pronunciationControllers.add(_PronunciationControllers.fromDraft(draft));
  }

  void _onCharacterChanged(String value) {
    final text = value.trim();
    _debounce?.cancel();
    if (text.runes.length != 1) return;
    _debounce = Timer(const Duration(milliseconds: 500), () => _lookup(text));
  }

  Future<void> _lookup(String character) async {
    setState(() {
      _loading = true;
      _message = '正在查询汉典...';
    });
    try {
      final result = await _zdic.fetch(character);
      for (final controller in _pronunciationControllers) {
        controller.dispose();
      }
      _pronunciationControllers
        ..clear()
        ..addAll(
          result.pronunciations.map(_PronunciationControllers.fromDraft),
        );
      setState(() {
        _glyphImageUrl = result.glyphImageUrl;
        _strokeGifUrl = result.strokeGifUrl;
        _message = '已自动填充拼音和基本解释';
      });
    } catch (error) {
      setState(() {
        _message = '自动查询失败，可手动填写';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final character = _characterController.text.trim();
    final existing = await AppDatabase.instance.findByCharacter(character);
    if (existing != null && existing.id != widget.existing?.id) {
      setState(() => _message = '这个生字已经记录过啦');
      return;
    }
    final now = DateTime.now();
    final id = widget.existing?.id ?? makeId('word');
    final pronunciations = <Pronunciation>[];
    for (var i = 0; i < _pronunciationControllers.length; i++) {
      final controller = _pronunciationControllers[i];
      if (controller.pinyin.text.trim().isEmpty &&
          controller.basicExplanation.text.trim().isEmpty) {
        continue;
      }
      pronunciations.add(
        Pronunciation(
          id: controller.id.isEmpty ? makeId('py') : controller.id,
          wordId: id,
          pinyin: controller.pinyin.text.trim(),
          zhuyin: controller.zhuyin.text.trim(),
          basicExplanation: controller.basicExplanation.text.trim(),
          sortOrder: i,
        ),
      );
    }
    final primary = pronunciations.isEmpty ? '' : pronunciations.first.pinyin;
    final word = WordEntry(
      id: id,
      character: character,
      glyphImageUrl: _glyphImageUrl,
      strokeGifUrl: _strokeGifUrl,
      primaryPinyin: primary,
      note: _noteController.text.trim(),
      isLearned: _isLearned,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
      pronunciations: pronunciations,
    );
    await AppDatabase.instance.upsertWord(word);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '编辑生字' : '添加生字')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GlyphBox(
                    word: WordEntry(
                      id: '',
                      character: _characterController.text.trim(),
                      glyphImageUrl: _glyphImageUrl,
                      strokeGifUrl: _strokeGifUrl,
                      primaryPinyin: '',
                      note: '',
                      isLearned: false,
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                      pronunciations: const [],
                    ),
                    size: 104,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextFormField(
                      controller: _characterController,
                      enabled: !_isEditing,
                      decoration: const InputDecoration(
                        labelText: '生字',
                        prefixIcon: Icon(Icons.edit_rounded),
                      ),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return '请输入一个生字';
                        if (text.runes.length != 1) return '第一版只支持单个汉字';
                        return null;
                      },
                      onChanged: _onCharacterChanged,
                    ),
                  ),
                ],
              ),
              if (_loading || _message != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (_loading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.info_rounded, size: 18, color: _blue),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_message ?? '')),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              ..._pronunciationControllers.indexed.map((item) {
                final index = item.$1;
                final controller = item.$2;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text(
                                '读音 ${index + 1}',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const Spacer(),
                              if (_pronunciationControllers.length > 1)
                                IconButton(
                                  tooltip: '删除读音',
                                  onPressed: () {
                                    setState(() {
                                      _pronunciationControllers
                                          .removeAt(index)
                                          .dispose();
                                    });
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: controller.pinyin,
                                  decoration: const InputDecoration(
                                    labelText: '拼音',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: controller.zhuyin,
                                  decoration: const InputDecoration(
                                    labelText: '注音',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: controller.basicExplanation,
                            minLines: 3,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              labelText: '基本解释',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              OutlinedButton.icon(
                onPressed: () => setState(_addPronunciation),
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加读音'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '备注',
                  prefixIcon: Icon(Icons.sticky_note_2_rounded),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _isLearned,
                onChanged: (value) => setState(() => _isLearned = value),
                title: const Text('已经学会'),
                secondary: const Icon(Icons.check_circle_rounded),
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _loading ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: const Text('保存'),
          ),
        ),
      ),
    );
  }
}

class WordDetailPage extends StatefulWidget {
  const WordDetailPage({required this.initialWordId, super.key});

  final String initialWordId;

  @override
  State<WordDetailPage> createState() => _WordDetailPageState();
}

class _WordDetailPageState extends State<WordDetailPage> {
  late String _wordId;
  late Future<_DetailData> _future;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _wordId = widget.initialWordId;
    _future = _load();
  }

  Future<_DetailData> _load() async {
    final hideLearned = await AppDatabase.instance.getHideLearnedWords();
    final words = await AppDatabase.instance.listWords(
      hideLearned: hideLearned,
    );
    final word = await AppDatabase.instance.getWord(_wordId);
    if (word == null) throw Exception('生字不存在');
    return _DetailData(word: word, orderedWords: words);
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _edit(WordEntry word) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => WordEditPage(existing: word)),
    );
    if (changed == true) {
      _changed = true;
      _refresh();
    }
  }

  Future<void> _delete(WordEntry word) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这个生字？'),
        content: Text('“${word.character}”会从小本本里移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AppDatabase.instance.deleteWord(word.id);
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  Future<void> _setLearned(WordEntry word, bool value) async {
    await AppDatabase.instance.updateLearned(word.id, value);
    _changed = true;
    _refresh();
  }

  void _move(_DetailData data, int delta) {
    final ids = data.orderedWords.map((w) => w.id).toList();
    final index = ids.indexOf(data.word.id);
    final next = index + delta;
    if (index == -1 || next < 0 || next >= ids.length) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已经到边界啦')));
      return;
    }
    setState(() {
      _wordId = ids[next];
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: FutureBuilder<_DetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final data = snapshot.data!;
          final word = data.word;
          return Scaffold(
            appBar: AppBar(
              title: Text(word.character),
              actions: [
                IconButton(
                  tooltip: '编辑',
                  onPressed: () => _edit(word),
                  icon: const Icon(Icons.edit_rounded),
                ),
                IconButton(
                  tooltip: '删除',
                  onPressed: () => _delete(word),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            body: SafeArea(
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity < -250) _move(data, 1);
                  if (velocity > 250) _move(data, -1);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            GlyphBox(word: word, size: 150),
                            const SizedBox(height: 12),
                            Text(
                              word.pinyinText,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: _blue,
                              ),
                            ),
                            const SizedBox(height: 10),
                            LearnedChip(isLearned: word.isLearned),
                            const SizedBox(height: 10),
                            SwitchListTile(
                              value: word.isLearned,
                              onChanged: (value) => _setLearned(word, value),
                              title: const Text('已经学会'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (final pronunciation in word.pronunciations) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [
                                  pronunciation.pinyin,
                                  pronunciation.zhuyin,
                                ].where((e) => e.isNotEmpty).join('  '),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: _green,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                pronunciation.basicExplanation.isEmpty
                                    ? '暂无解释'
                                    : pronunciation.basicExplanation,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.55,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (word.note.isNotEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '备注',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(word.note),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _move(data, -1),
                            icon: const Icon(Icons.chevron_left_rounded),
                            label: const Text('上一个'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _move(data, 1),
                            icon: const Icon(Icons.chevron_right_rounded),
                            label: const Text('下一个'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DetailData {
  _DetailData({required this.word, required this.orderedWords});

  final WordEntry word;
  final List<WordEntry> orderedWords;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _hideLearned = false;
  bool _loaded = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await AppDatabase.instance.getHideLearnedWords();
    setState(() {
      _hideLearned = value;
      _loaded = true;
    });
  }

  Future<void> _set(bool value) async {
    await AppDatabase.instance.setHideLearnedWords(value);
    setState(() {
      _hideLearned = value;
      _changed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('配置')),
        body: SafeArea(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: SwitchListTile(
                        value: _hideLearned,
                        onChanged: _set,
                        secondary: const Icon(
                          Icons.visibility_off_rounded,
                          color: _green,
                        ),
                        title: const Text(
                          '隐藏已学会生字',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: const Text('开启后，列表、搜索和详情滑动都会跳过已学会的生字。'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class GlyphBox extends StatefulWidget {
  const GlyphBox({required this.word, required this.size, super.key});

  final WordEntry word;
  final double size;

  @override
  State<GlyphBox> createState() => _GlyphBoxState();
}

class _GlyphBoxState extends State<GlyphBox> {
  bool _showStroke = false;

  @override
  Widget build(BuildContext context) {
    final glyphUrl = widget.word.glyphImageUrl;
    final strokeUrl = widget.word.strokeGifUrl;
    final canPlayStroke = strokeUrl.isNotEmpty;
    final content = _showStroke && canPlayStroke
        ? Image.network(
            strokeUrl,
            width: widget.size * 0.82,
            height: widget.size * 0.82,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _fallbackGlyph(),
          )
        : glyphUrl.endsWith('.svg')
        ? SvgPicture.network(
            glyphUrl,
            width: widget.size * 0.75,
            height: widget.size * 0.75,
            placeholderBuilder: (_) => _fallbackGlyph(),
          )
        : _fallbackGlyph();

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: canPlayStroke
          ? () => setState(() => _showStroke = !_showStroke)
          : null,
      child: Stack(
        children: [
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _orange.withValues(alpha: 0.45),
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: content,
          ),
          if (canPlayStroke)
            Positioned(
              right: 5,
              bottom: 5,
              child: Container(
                width: widget.size < 80 ? 24 : 32,
                height: widget.size < 80 ? 24 : 32,
                decoration: BoxDecoration(
                  color: (_showStroke ? _green : _blue).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  _showStroke ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: widget.size < 80 ? 18 : 23,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fallbackGlyph() {
    return Text(
      widget.word.character.isEmpty ? '?' : widget.word.character,
      style: TextStyle(
        fontSize: widget.size * 0.58,
        fontWeight: FontWeight.w900,
        color: _ink,
      ),
    );
  }
}

class LearnedChip extends StatelessWidget {
  const LearnedChip({required this.isLearned, super.key});

  final bool isLearned;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isLearned
            ? _green.withValues(alpha: 0.14)
            : _orange.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isLearned ? '已会' : '未会',
        style: TextStyle(
          color: isLearned ? _green : const Color(0xFFB87500),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PronunciationControllers {
  _PronunciationControllers({
    required this.id,
    required this.pinyin,
    required this.zhuyin,
    required this.basicExplanation,
  });

  factory _PronunciationControllers.fromDraft(PronunciationDraft? draft) {
    return _PronunciationControllers(
      id: '',
      pinyin: TextEditingController(text: draft?.pinyin ?? ''),
      zhuyin: TextEditingController(text: draft?.zhuyin ?? ''),
      basicExplanation: TextEditingController(
        text: draft?.basicExplanation ?? '',
      ),
    );
  }

  factory _PronunciationControllers.fromPronunciation(Pronunciation value) {
    return _PronunciationControllers(
      id: value.id,
      pinyin: TextEditingController(text: value.pinyin),
      zhuyin: TextEditingController(text: value.zhuyin),
      basicExplanation: TextEditingController(text: value.basicExplanation),
    );
  }

  final String id;
  final TextEditingController pinyin;
  final TextEditingController zhuyin;
  final TextEditingController basicExplanation;

  void dispose() {
    pinyin.dispose();
    zhuyin.dispose();
    basicExplanation.dispose();
  }
}

String makeId(String prefix) {
  return '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
}

String cleanText(String text) {
  return text.replaceAll('\u00a0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

String pinyinInitials(String text) {
  final normalized = text
      .toLowerCase()
      .replaceAll(RegExp('[āáǎà]'), 'a')
      .replaceAll(RegExp('[ēéěè]'), 'e')
      .replaceAll(RegExp('[īíǐì]'), 'i')
      .replaceAll(RegExp('[ōóǒò]'), 'o')
      .replaceAll(RegExp('[ūúǔù]'), 'u')
      .replaceAll(RegExp('[ǖǘǚǜü]'), 'v');
  return normalized
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0])
      .join();
}

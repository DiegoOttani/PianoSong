import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../core/keyboard_layout.dart';
import '../song/difficulty_generator.dart';
import '../song/midi_importer.dart';
import '../song/range_fitter.dart';
import '../song/song_model.dart';
import 'demo_songs.dart';

class SongEntry {
  SongEntry({
    required this.id,
    required this.title,
    required this.source,
    this.parts = const {},
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  final String id;
  String title;

  /// 'demo', 'bitmidi' ou 'arquivo'.
  final String source;

  /// Partes do MIDI escolhidas (track, canal).
  Set<(int, int)> parts;
  final DateTime addedAt;

  bool get isDemo => source == 'demo';

  Map<String, Object> toJson() => {
        'id': id,
        'title': title,
        'source': source,
        'parts': [for (final p in parts) [p.$1, p.$2]],
        'addedAt': addedAt.toIso8601String(),
      };

  factory SongEntry.fromJson(Map<String, dynamic> j) => SongEntry(
        id: j['id'] as String,
        title: j['title'] as String,
        source: j['source'] as String,
        parts: {
          for (final p in (j['parts'] as List? ?? const []))
            ((p as List)[0] as int, p[1] as int),
        },
        addedAt: DateTime.tryParse(j['addedAt'] as String? ?? ''),
      );
}

class SessionResult {
  const SessionResult({
    required this.songId,
    required this.difficulty,
    required this.score,
    required this.accuracy,
    required this.stars,
    required this.maxCombo,
    required this.speed,
    required this.at,
  });

  final String songId;
  final Difficulty difficulty;
  final int score;
  final double accuracy;
  final int stars;
  final int maxCombo;
  final double speed;
  final DateTime at;

  Map<String, Object> toJson() => {
        'song': songId,
        'diff': difficulty.index,
        'score': score,
        'acc': accuracy,
        'stars': stars,
        'combo': maxCombo,
        'speed': speed,
        'at': at.toIso8601String(),
      };

  factory SessionResult.fromJson(Map<String, dynamic> j) => SessionResult(
        songId: j['song'] as String,
        difficulty: Difficulty.values[j['diff'] as int],
        score: j['score'] as int,
        accuracy: (j['acc'] as num).toDouble(),
        stars: j['stars'] as int,
        maxCombo: j['combo'] as int,
        speed: (j['speed'] as num).toDouble(),
        at: DateTime.parse(j['at'] as String),
      );
}

/// Biblioteca de músicas e progresso, salvos em arquivos JSON no aparelho.
/// Os MIDIs ficam só no celular (nada vai para o repositório).
class SongRepository {
  SongRepository._(this._dir);

  static Future<SongRepository> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/pianosong');
    await Directory('${dir.path}/midi').create(recursive: true);
    final repo = SongRepository._(dir);
    await repo._load();
    return repo;
  }

  final Directory _dir;
  final List<SongEntry> entries = [];
  final List<SessionResult> history = [];

  File get _libraryFile => File('${_dir.path}/library.json');
  File get _historyFile => File('${_dir.path}/history.json');
  File _midiFile(String id) => File('${_dir.path}/midi/$id.mid');

  Future<void> _load() async {
    if (await _libraryFile.exists()) {
      final list = jsonDecode(await _libraryFile.readAsString()) as List;
      entries.addAll(list.map((e) => SongEntry.fromJson(e as Map<String, dynamic>)));
    }
    for (final id in DemoSongs.titles.keys) {
      if (!entries.any((e) => e.id == id)) {
        entries.add(SongEntry(id: id, title: DemoSongs.titles[id]!, source: 'demo'));
      }
    }
    if (await _historyFile.exists()) {
      final list = jsonDecode(await _historyFile.readAsString()) as List;
      history.addAll(list.map((e) => SessionResult.fromJson(e as Map<String, dynamic>)));
    }
  }

  Future<void> _saveLibrary() =>
      _libraryFile.writeAsString(jsonEncode([for (final e in entries) e.toJson()]));

  Future<void> _saveHistory() =>
      _historyFile.writeAsString(jsonEncode([for (final h in history) h.toJson()]));

  Future<SongEntry> addMidi({
    required String id,
    required String title,
    required String source,
    required Uint8List bytes,
    required Set<(int, int)> parts,
  }) async {
    await _midiFile(id).writeAsBytes(bytes);
    entries.removeWhere((e) => e.id == id);
    final entry = SongEntry(id: id, title: title, source: source, parts: parts);
    entries.insert(0, entry);
    await _saveLibrary();
    return entry;
  }

  Future<void> update(SongEntry entry) => _saveLibrary();

  Future<void> remove(SongEntry entry) async {
    entries.remove(entry);
    final f = _midiFile(entry.id);
    if (await f.exists()) await f.delete();
    history.removeWhere((h) => h.songId == entry.id);
    await _saveLibrary();
    await _saveHistory();
  }

  Future<Uint8List?> midiBytes(SongEntry entry) async {
    final f = _midiFile(entry.id);
    return await f.exists() ? f.readAsBytes() : null;
  }

  /// Música completa (nível Original) já ajustada ao teclado.
  Future<FitResult> loadSong(SongEntry entry, KeyboardSize keyboard) async {
    Song song;
    if (entry.isDemo) {
      song = DemoSongs.byId(entry.id)!;
    } else {
      final bytes = await midiBytes(entry);
      if (bytes == null) throw Exception('Arquivo da música não encontrado');
      final midi = MidiImporter.parse(bytes);
      song = MidiImporter.toSong(
        midi,
        title: entry.title,
        selection: entry.parts.isEmpty ? null : entry.parts,
      );
    }
    return RangeFitter.fit(song, keyboard);
  }

  Future<void> addResult(SessionResult r) async {
    history.add(r);
    await _saveHistory();
  }

  List<SessionResult> resultsFor(String songId, [Difficulty? d]) => history
      .where((h) => h.songId == songId && (d == null || h.difficulty == d))
      .toList();

  int bestStars(String songId, Difficulty d) =>
      resultsFor(songId, d).fold(0, (m, r) => r.stars > m ? r.stars : m);

  int bestScore(String songId, Difficulty d) =>
      resultsFor(songId, d).fold(0, (m, r) => r.score > m ? r.score : m);

  /// Um nível é liberado com 3 estrelas no anterior (ou se tudo estiver liberado).
  bool isUnlocked(String songId, Difficulty d, {bool unlockAll = false}) {
    if (unlockAll || d.index == 0) return true;
    return bestStars(songId, Difficulty.values[d.index - 1]) >= 3;
  }

  /// Dias seguidos com pelo menos uma sessão (contando hoje ou ontem).
  int get streakDays {
    final days = history.map((h) => DateTime(h.at.year, h.at.month, h.at.day)).toSet();
    var day = DateTime.now();
    day = DateTime(day.year, day.month, day.day);
    if (!days.contains(day)) day = day.subtract(const Duration(days: 1));
    var count = 0;
    while (days.contains(day)) {
      count++;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }
}

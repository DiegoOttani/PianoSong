// Teste com a internet: busca e importa um MIDI real do BitMidi.
// Só roda com: flutter test test/bitmidi_live_test.dart --dart-define=LIVE=true
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_song/core/keyboard_layout.dart';
import 'package:piano_song/library/bitmidi_api.dart';
import 'package:piano_song/song/difficulty_generator.dart';
import 'package:piano_song/song/midi_importer.dart';
import 'package:piano_song/song/range_fitter.dart';

const live = bool.fromEnvironment('LIVE');

void main() {
  test('busca, baixa e importa', () async {
    final api = BitMidiApi();
    for (final q in ['fur elise', 'river flows in you']) {
      final page = await api.search(q);
      expect(page.results, isNotEmpty);
      final r = page.results.first;
      final bytes = await api.download(r);
      final midi = MidiImporter.parse(bytes);
      final parts = MidiImporter.parts(midi);
      final song = MidiImporter.toSong(midi, title: r.title);
      final fit = RangeFitter.fit(song, KeyboardSize.keys61);
      final counts = [
        for (final d in Difficulty.values) DifficultyGenerator.generate(fit.song, d).notes.length
      ];
      // ignore: avoid_print
      print('${r.name}: ${parts.length} partes '
          '(${parts.map((p) => '${p.instrument}:${p.noteCount}').join(', ')}), '
          '${(song.durationMs / 1000).round()}s, ${song.initialBpm} BPM, '
          'oitavas ${fit.octaveShift}, dobradas ${fit.foldedNotes}, níveis $counts');
      expect(counts.last, greaterThan(counts.first));
    }
  }, skip: !live, timeout: const Timeout(Duration(minutes: 2)));
}

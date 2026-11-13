import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piano_song/core/keyboard_layout.dart';
import 'package:piano_song/core/note.dart';
import 'package:piano_song/game/falling_notes_painter.dart';
import 'package:piano_song/game/game_engine.dart';
import 'package:piano_song/library/demo_songs.dart';
import 'package:piano_song/song/difficulty_generator.dart';
import 'package:piano_song/song/range_fitter.dart';

void main() {
  for (final id in DemoSongs.titles.keys) {
    test('demo $id cabe em 61 teclas e gera os 4 níveis', () {
      final song = DemoSongs.byId(id)!;
      expect(RangeFitter.fit(song, KeyboardSize.keys61).foldedNotes, 0);
      for (final d in Difficulty.values) {
        expect(DifficultyGenerator.generate(song, d).notes, isNotEmpty);
      }
    });
  }

  testWidgets('desenha o jogo em vários momentos sem erro', (tester) async {
    final song = DemoSongs.byId(DemoSongs.odeId)!;
    final engine = GameEngine(GameConfig(song: song, speed: 0.8, waitMode: false));
    final repaint = ValueNotifier(0);
    final flashes = {60: KeyFlash(Colors.amber, 0, label: 'Perfeito')};
    await tester.binding.setSurfaceSize(const Size(900, 420));
    await tester.pumpWidget(CustomPaint(
      size: const Size(900, 420),
      painter: FallingNotesPainter(
        engine: engine,
        keyboard: KeyboardSize.keys61,
        naming: NoteNaming.solfege,
        flashes: flashes,
        nowMs: () => 100,
        beatFlash: true,
        repaint: repaint,
      ),
    ));
    for (var i = 0; i < 40; i++) {
      engine.tick(500);
      engine.notePlayed(64);
      repaint.value++;
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });
}

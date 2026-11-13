import 'package:flutter_test/flutter_test.dart';
import 'package:piano_song/core/keyboard_layout.dart';
import 'package:piano_song/core/note.dart';

void main() {
  group('Note', () {
    test('nomes', () {
      expect(Note.name(60, NoteNaming.solfege), 'Dó');
      expect(Note.name(61, NoteNaming.letters), 'C♯');
      expect(Note.name(69, NoteNaming.solfege, withOctave: true), 'Lá4');
      expect(Note.name(60, NoteNaming.none), '');
    });

    test('frequência ida e volta', () {
      expect(Note.frequency(69), closeTo(440, 0.001));
      expect(Note.frequency(60), closeTo(261.63, 0.01));
      for (var m = 21; m <= 108; m++) {
        expect(Note.fromFrequency(Note.frequency(m)), m);
      }
    });

    test('teclas pretas', () {
      expect(Note.isBlack(61), isTrue);
      expect(Note.isBlack(64), isFalse);
    });
  });

  group('Teclado', () {
    test('quantidade de teclas bate com a faixa', () {
      for (final s in KeyboardSize.values) {
        expect(s.highest - s.lowest + 1, s.keys, reason: s.label);
      }
      expect(KeyboardSize.keys61.whiteKeyCount, 36);
      expect(KeyboardSize.keys88.whiteKeyCount, 52);
    });

    test('geometria ocupa a largura e encontra teclas', () {
      final g = KeyboardGeometry(KeyboardSize.keys61, 720);
      expect(g.whiteKeyWidth, closeTo(20, 1e-9));
      expect(g.rectFor(36)!.left, 0);
      expect(g.rectFor(96)!.right, closeTo(720, 1e-9));
      final cSharp = g.rectFor(37)!;
      expect(g.keyAt(cSharp.center, preferBlack: true), 37);
      expect(g.keyAt(cSharp.center), anyOf(36, 38));
    });
  });
}

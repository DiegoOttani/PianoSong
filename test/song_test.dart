import 'package:flutter_test/flutter_test.dart';
import 'package:piano_song/core/keyboard_layout.dart';
import 'package:piano_song/song/difficulty_generator.dart';
import 'package:piano_song/song/hand_splitter.dart';
import 'package:piano_song/song/midi_importer.dart';
import 'package:piano_song/song/midi_parser.dart';
import 'package:piano_song/song/range_fitter.dart';
import 'package:piano_song/song/song_model.dart';

import 'helpers/midi_builder.dart';

NoteEvent n(int pitch, int start, {int dur = 400, Hand hand = Hand.right}) =>
    NoteEvent(pitch: pitch, startMs: start, durationMs: dur, hand: hand);

void main() {
  group('MidiParser', () {
    test('lê notas, tempo e running status', () {
      final b = MidiBuilder();
      final t = b.track()..useRunningStatus = true;
      t.tempo(0, 120);
      t.note(0, 480, 60, zeroVelOff: true);
      t.note(480, 480, 62, zeroVelOff: true);
      t.note(960, 240, 64, zeroVelOff: true);
      final midi = MidiParser.parse(b.build());
      expect(midi.notes.map((n) => n.pitch), [60, 62, 64]);
      expect(midi.tempoMap.msAt(480), closeTo(500, 1e-6));
      expect(midi.notes.last.endTick - midi.notes.last.startTick, 240);
    });

    test('mudança de andamento', () {
      final b = MidiBuilder();
      final t = b.track();
      t.tempo(0, 120); // 500 ms por tempo
      t.tempo(960, 60); // 1000 ms por tempo
      t.note(1440, 480, 60);
      final midi = MidiParser.parse(b.build());
      expect(midi.tempoMap.msAt(960), closeTo(1000, 1e-6));
      expect(midi.tempoMap.msAt(1440), closeTo(2000, 1e-6));
    });

    test('rejeita arquivo inválido', () {
      expect(() => MidiParser.parse(MidiBuilder().build().sublist(0, 10)),
          throwsA(isA<MidiFormatException>()));
    });
  });

  group('MidiImporter', () {
    test('seleciona pianos e ignora bateria', () {
      final b = MidiBuilder();
      final meta = b.track()..tempo(0, 120)..timeSig(0, 4, 4);
      meta.name('Meta');
      final piano = b.track()..name('Piano')..program(0, 0, 0);
      piano.note(0, 480, 72);
      final guitar = b.track()..program(0, 1, 25);
      guitar.note(0, 480, 64, channel: 1);
      final drums = b.track();
      drums.note(0, 100, 36, channel: 9);

      final midi = MidiImporter.parse(b.build());
      final parts = MidiImporter.parts(midi);
      expect(parts.length, 3);
      expect(parts.firstWhere((p) => p.channel == 9).instrument, 'Bateria');
      expect(MidiImporter.defaultSelection(parts), {(1, 0)});

      final song = MidiImporter.toSong(midi, title: 'x');
      expect(song.notes.map((n) => n.pitch), [72]);
      expect(song.barsMs.take(2), [0, 2000]);
      expect(song.initialBpm, 120);
    });

    test('duas partes de piano viram duas mãos', () {
      final b = MidiBuilder();
      final rh = b.track()..program(0, 0, 0);
      rh.note(0, 480, 60); // Dó central, mas a parte é mais aguda
      rh.note(480, 480, 72);
      final lh = b.track()..program(0, 1, 0);
      lh.note(0, 480, 48, channel: 1);
      lh.note(480, 480, 43, channel: 1);
      final song = MidiImporter.toSong(MidiImporter.parse(b.build()), title: 'x');
      expect(song.notes.where((n) => n.hand == Hand.right).map((n) => n.pitch).toSet(), {60, 72});
      expect(song.notes.where((n) => n.hand == Hand.left).map((n) => n.pitch).toSet(), {48, 43});
    });
  });

  group('HandSplitter', () {
    test('agudo direita, grave esquerda, histerese no meio', () {
      final out = HandSplitter.split([
        n(72, 0), n(48, 0), // claro
        n(62, 500), // zona ambígua: mais perto da direita (72) que da esquerda (48)
        n(55, 1000), // grave -> esquerda (última posição da esquerda = 55)
        n(57, 1500), // zona ambígua: mais perto da esquerda (55) que da direita (62)
      ]);
      Hand handOf(int p) => out.firstWhere((e) => e.pitch == p).hand;
      expect(handOf(72), Hand.right);
      expect(handOf(48), Hand.left);
      expect(handOf(62), Hand.right);
      expect(handOf(57), Hand.left);
    });

    test('mão direita não abre mais que 14 semitons', () {
      final out = HandSplitter.split([n(64, 0), n(70, 0), n(84, 0)]);
      final right = out.where((e) => e.hand == Hand.right).map((e) => e.pitch).toList();
      expect(right.last - right.first, lessThanOrEqualTo(14));
    });
  });

  group('RangeFitter', () {
    test('transpõe e dobra para caber', () {
      final song = Song(title: 't', notes: [n(100, 0), n(104, 500), n(110, 1000), n(60, 1500)]);
      final fit = RangeFitter.fit(song, KeyboardSize.keys61);
      expect(fit.song.notes.every((e) => KeyboardSize.keys61.contains(e.pitch)), isTrue);
      expect(fit.song.notes.length, 4);
      expect(fit.octaveShift, -2); // -2 oitavas: todas as 4 notas cabem
      expect(fit.foldedNotes, 0);
    });

    test('dobra por oitava quando não dá para transpor tudo', () {
      final song = Song(title: 't', notes: [n(100, 0), n(30, 500)]);
      final fit = RangeFitter.fit(song, KeyboardSize.keys61);
      expect(fit.song.notes.map((e) => e.pitch), [88, 42]);
      expect(fit.octaveShift, -1); // 100->88 cabe; 30->18 precisa dobrar
      expect(fit.foldedNotes, 1);
    });
  });

  group('DifficultyGenerator', () {
    Song sample() {
      // 4/4 a 120 BPM: tempo = 500 ms, compasso = 2000 ms.
      final notes = <NoteEvent>[];
      for (var i = 0; i < 32; i++) {
        final t = i * 250; // colcheias
        notes.add(n(72 + i % 5, t, dur: 240));
        notes.add(n(67 + i % 3, t, dur: 240)); // acorde na direita
        notes.add(n(64, t, dur: 240));
        if (i % 2 == 0) {
          notes
            ..add(n(48, t, hand: Hand.left))
            ..add(n(52, t, hand: Hand.left))
            ..add(n(55, t, hand: Hand.left));
        }
      }
      return Song(
        title: 's',
        notes: notes,
        beatsMs: [for (var i = 0; i <= 20; i++) i * 500],
        barsMs: [for (var i = 0; i <= 5; i++) i * 2000],
      );
    }

    test('níveis têm cada vez mais notas', () {
      final s = sample();
      final counts = [for (final d in Difficulty.values) DifficultyGenerator.generate(s, d).notes.length];
      for (var i = 1; i < counts.length; i++) {
        expect(counts[i], greaterThanOrEqualTo(counts[i - 1]), reason: '$counts');
      }
      expect(counts.first, lessThan(counts.last));
    });

    test('iniciante: só mão direita, uma nota por vez, sem notas mais rápidas que meio tempo', () {
      final notes = DifficultyGenerator.generate(sample(), Difficulty.beginner).notes;
      expect(notes.every((e) => e.hand == Hand.right), isTrue);
      for (var i = 1; i < notes.length; i++) {
        expect(notes[i].startMs - notes[i - 1].startMs, greaterThanOrEqualTo(237));
      }
    });

    test('fácil: baixo só no começo dos compassos', () {
      final notes = DifficultyGenerator.generate(sample(), Difficulty.easy).notes;
      final left = notes.where((e) => e.hand == Hand.left).toList();
      expect(left.map((e) => e.startMs), [0, 2000, 4000, 6000]);
      expect(left.every((e) => e.pitch == 48), isTrue);
    });

    test('médio: no máximo 2 notas por mão em cada acorde', () {
      final notes = DifficultyGenerator.generate(sample(), Difficulty.medium).notes;
      for (final chord in groupChords(notes)) {
        expect(chord.where((e) => e.hand == Hand.right).length, lessThanOrEqualTo(2));
        expect(chord.where((e) => e.hand == Hand.left).length, lessThanOrEqualTo(2));
      }
    });
  });

  test('Song JSON ida e volta', () {
    final s = Song(title: 'a', notes: [n(60, 0)], beatsMs: [0, 500], barsMs: [0]);
    final back = Song.fromJson(s.toJson());
    expect(back.notes.single.pitch, 60);
    expect(back.beatsMs, [0, 500]);
  });
}

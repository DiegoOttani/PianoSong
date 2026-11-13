import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_song/core/note.dart';
import 'package:piano_song/detection/fft.dart';
import 'package:piano_song/detection/note_analyzer.dart';

const sr = 44100.0;
const size = 4096;

/// Som parecido com teclado: harmônicos decrescentes + um pouco de ruído.
Float64List tone(List<int> midis, {double amp = 0.2, int seed = 1, double fundamental = 1.0}) {
  final rnd = math.Random(seed);
  final out = Float64List(size);
  for (var i = 0; i < size; i++) {
    final t = i / sr;
    var v = (rnd.nextDouble() - 0.5) * 0.002;
    for (final m in midis) {
      final f = Note.frequency(m);
      for (var h = 1; h <= 8; h++) {
        if (f * h > sr / 2) break;
        final a = (h == 1 ? fundamental : 1.0) * amp / h;
        v += a * math.sin(2 * math.pi * f * h * t + h);
      }
    }
    out[i] = v;
  }
  return out;
}

void main() {
  final fft = SpectrumAnalyzer(size);
  final analyzer = NoteAnalyzer(sampleRate: sr, fftSize: size);

  test('FFT encontra o pico certo', () {
    final s = Float64List(size);
    for (var i = 0; i < size; i++) {
      s[i] = math.sin(2 * math.pi * 1000 * i / sr);
    }
    final mags = fft.magnitudes(s);
    var peak = 0;
    for (var i = 1; i < mags.length; i++) {
      if (mags[i] > mags[peak]) peak = i;
    }
    expect(peak * sr / size, closeTo(1000, sr / size));
  });

  group('detecção livre (nota mais forte)', () {
    for (final midi in [36, 43, 48, 55, 60, 64, 67, 72, 79, 84, 96]) {
      test(Note.name(midi, NoteNaming.solfege, withOctave: true), () {
        final mags = fft.magnitudes(tone([midi]));
        final s = analyzer.strongest(mags, lowest: 36, highest: 96)!;
        expect(s.midi, midi);
      });
    }

    test('grave com fundamental fraca (microfone de celular)', () {
      final mags = fft.magnitudes(tone([40], fundamental: 0.1));
      expect(analyzer.strongest(mags, lowest: 36, highest: 96)!.midi, 40);
    });

    test('silêncio não detecta nada', () {
      final mags = fft.magnitudes(tone([], amp: 0));
      expect(analyzer.strongest(mags, lowest: 36, highest: 96, minLevel: 2), isNull);
    });
  });

  test('acorde: notas esperadas se destacam das que não estão soando', () {
    final mags = fft.magnitudes(tone([60, 64, 67], amp: 0.12));
    final playing = [60, 64, 67].map((m) => analyzer.level(mags, m)).reduce(math.min);
    final notPlaying = [59, 61, 62, 63, 65, 66, 68, 69].map((m) => analyzer.level(mags, m)).reduce(math.max);
    expect(playing, greaterThan(notPlaying));
  });

  test('ataque: conta uma vez enquanto a nota é segurada', () {
    final tracker = OnsetTracker();
    final silent = analyzer.levels(fft.magnitudes(tone([], amp: 0)), [60]);
    final held = analyzer.levels(fft.magnitudes(tone([60])), [60]);
    double th(int _) => 2.0;

    for (var i = 0; i < 6; i++) {
      expect(tracker.update(silent, th), isEmpty);
    }
    expect(tracker.update(held, th), {60});
    for (var i = 0; i < 20; i++) {
      expect(tracker.update(held, th), isEmpty, reason: 'quadro $i');
    }
    for (var i = 0; i < 6; i++) {
      tracker.update(silent, th);
    }
    expect(tracker.update(held, th), {60}, reason: 'tocou de novo');
  });
}

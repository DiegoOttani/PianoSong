import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_song/audio/piano_synth.dart';
import 'package:piano_song/detection/fft.dart';
import 'package:piano_song/detection/note_analyzer.dart';

void main() {
  test('WAV válido e sem estourar', () {
    final wav = PianoSynth.renderWav(60);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    final samples = PianoSynth.render(60);
    expect(samples.every((s) => s.abs() <= 0.7), isTrue);
    expect(samples.length, (PianoSynth.durationFor(60) * PianoSynth.sampleRate).round());
  });

  test('o som gerado tem a altura certa (o próprio detector reconhece)', () {
    final fft = SpectrumAnalyzer(4096);
    final analyzer = NoteAnalyzer(sampleRate: PianoSynth.sampleRate.toDouble(), fftSize: 4096);
    for (final midi in [36, 48, 55, 60, 64, 72, 84, 96]) {
      final s = PianoSynth.render(midi);
      // Janela logo depois do ataque.
      final window = Float64List.sublistView(s, 2000, 2000 + 4096);
      final best = analyzer.strongest(fft.magnitudes(window), lowest: 36, highest: 96)!;
      expect(best.midi, midi, reason: 'nota $midi');
    }
  });

  test('o som decai (graves duram mais que agudos)', () {
    double tailRms(int midi) {
      final s = PianoSynth.render(midi);
      final start = (1.0 * PianoSynth.sampleRate).round();
      var sum = 0.0;
      for (var i = start; i < start + 2000; i++) {
        sum += s[i] * s[i];
      }
      return sum / 2000;
    }

    final attack = PianoSynth.render(60).sublist(500, 2500).fold<double>(0, (a, v) => a + v * v) / 2000;
    expect(tailRms(60), lessThan(attack));
    expect(tailRms(40), greaterThan(tailRms(84)));
  });
}

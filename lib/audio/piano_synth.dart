import 'dart:math' as math;
import 'dart:typed_data';

import '../core/note.dart';

/// Gera o som de uma nota de piano por síntese aditiva (sem samples externos).
///
/// - Harmônicos levemente "esticados" (inarmonicidade de corda de piano).
/// - Agudos dos harmônicos somem mais rápido que a fundamental.
/// - Queda em dois estágios (ataque forte que cai rápido + sustentação longa).
/// - Um pouco de ruído de martelo no começo.
abstract final class PianoSynth {
  static const sampleRate = 44100;

  /// Duração do som gerado (graves soam mais tempo).
  static double durationFor(int midi) => (3.6 - (midi - 21) * 0.03).clamp(1.2, 3.6);

  static Float64List render(int midi) {
    final f0 = Note.frequency(midi);
    final seconds = durationFor(midi);
    final n = (seconds * sampleRate).round();
    final out = Float64List(n);

    // Inarmonicidade: maior nos agudos.
    final b = 0.00008 * math.pow(2, (midi - 21) / 24);
    final rnd = math.Random(midi);

    // Tempos de queda (s): graves duram mais.
    final tauSlow = (2.6 - (midi - 21) * 0.022).clamp(0.5, 2.6);
    final tauFast = tauSlow * 0.12;

    final maxPartials = midi < 48 ? 14 : (midi < 72 ? 10 : 6);
    for (var k = 1; k <= maxPartials; k++) {
      final fk = k * f0 * math.sqrt(1 + b * k * k);
      if (fk > sampleRate * 0.45) break;
      // Graves têm fundamental fraca e harmônicos fortes; agudos, o contrário.
      final tilt = midi < 48 ? 1.0 : 1.4;
      var amp = 1 / math.pow(k, tilt);
      if (midi < 40 && k == 1) amp *= 0.6;
      final decayK = 1 + 0.35 * (k - 1);
      final ts = tauSlow / decayK;
      final tf = tauFast / decayK;

      // Oscilador por rotação (mais rápido que sin() a cada amostra).
      final w = 2 * math.pi * fk / sampleRate;
      final c = math.cos(w), s = math.sin(w);
      final phase = rnd.nextDouble() * 2 * math.pi;
      var re = math.cos(phase), im = math.sin(phase);
      final kFast = math.exp(-1 / (tf * sampleRate));
      final kSlow = math.exp(-1 / (ts * sampleRate));
      var eFast = 0.65 * amp, eSlow = 0.35 * amp;
      for (var i = 0; i < n; i++) {
        out[i] += im * (eFast + eSlow);
        final r2 = re * c - im * s;
        im = re * s + im * c;
        re = r2;
        eFast *= kFast;
        eSlow *= kSlow;
      }
    }

    // Ruído de martelo (~8 ms) e ataque de 3 ms.
    final hammer = (0.012 * sampleRate).round();
    var lp = 0.0;
    for (var i = 0; i < hammer && i < n; i++) {
      lp += 0.3 * ((rnd.nextDouble() * 2 - 1) - lp);
      out[i] += lp * 0.25 * (1 - i / hammer);
    }
    final attack = (0.003 * sampleRate).round();
    for (var i = 0; i < attack && i < n; i++) {
      out[i] *= i / attack;
    }
    // Fim suave (80 ms).
    final release = (0.08 * sampleRate).round();
    for (var i = 0; i < release && i < n; i++) {
      out[n - 1 - i] *= i / release;
    }

    // Normaliza com compensação de volume (agudos soam mais alto ao ouvido).
    var peak = 0.0;
    for (final v in out) {
      if (v.abs() > peak) peak = v.abs();
    }
    final loud = (0.55 - (midi - 60) * 0.004).clamp(0.35, 0.65);
    final gain = peak == 0 ? 0.0 : loud / peak;
    for (var i = 0; i < n; i++) {
      out[i] *= gain;
    }
    return out;
  }

  /// WAV PCM 16-bit mono.
  static Uint8List renderWav(int midi) => toWav(render(midi));

  static Uint8List toWav(Float64List samples) {
    final dataLen = samples.length * 2;
    final b = ByteData(44 + dataLen);
    void ascii(int off, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(off + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    b.setUint32(4, 36 + dataLen, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, 1, Endian.little); // mono
    b.setUint32(24, sampleRate, Endian.little);
    b.setUint32(28, sampleRate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    b.setUint32(40, dataLen, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      b.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    }
    return b.buffer.asUint8List();
  }
}

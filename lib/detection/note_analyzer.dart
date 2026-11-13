import 'dart:math' as math;
import 'dart:typed_data';

import '../core/note.dart';

/// Mede, a partir de um espectro, o quanto cada nota está soando.
///
/// O "nível" de uma nota é a soma ponderada (em escala log) da energia nos
/// seus harmônicos. Uma nota tocada tem todos os harmônicos; a oitava de
/// baixo (sub-harmônico) só tem os pares, então perde. Para notas graves,
/// onde a FFT não separa semitons na fundamental, os harmônicos altos fazem a
/// diferença.
class NoteAnalyzer {
  NoteAnalyzer({required this.sampleRate, required this.fftSize, this.harmonics = 6});

  final double sampleRate;
  final int fftSize;
  final int harmonics;

  static const _weights = [1.0, 0.9, 0.75, 0.6, 0.5, 0.4, 0.35, 0.3];

  double get binHz => sampleRate / fftSize;

  /// Magnitude máxima em volta da frequência (±meio semitom, no mínimo 1 bin).
  double _peakAt(Float64List mags, double hz) {
    final center = hz / binHz;
    final halfWidth = math.max(1.0, center * 0.025);
    final lo = (center - halfWidth).floor().clamp(1, mags.length - 1);
    final hi = (center + halfWidth).ceil().clamp(1, mags.length - 1);
    var best = 0.0;
    for (var i = lo; i <= hi; i++) {
      if (mags[i] > best) best = mags[i];
    }
    return best;
  }

  /// Nível de uma nota. [noise] é a magnitude de referência do ruído.
  double level(Float64List mags, int midi, {double noise = 1e-4}) {
    final f0 = Note.frequency(midi);
    var sum = 0.0;
    var weightSum = 0.0;
    for (var h = 1; h <= harmonics; h++) {
      final f = f0 * h;
      if (f >= sampleRate / 2 * 0.95) break;
      final w = _weights[h - 1];
      sum += w * math.log(1 + _peakAt(mags, f) / noise);
      weightSum += w;
    }
    return weightSum == 0 ? 0 : sum / weightSum;
  }

  Map<int, double> levels(Float64List mags, Iterable<int> midis, {double noise = 1e-4}) =>
      {for (final m in midis) m: level(mags, m, noise: noise)};

  /// Saliência: quanto a nota se destaca dos semitons vizinhos (>1 = destaca).
  double salience(Float64List mags, int midi, {double noise = 1e-4}) {
    final l = level(mags, midi, noise: noise);
    final n = math.max(level(mags, midi - 1, noise: noise), level(mags, midi + 1, noise: noise));
    return l / math.max(n, 0.05);
  }

  /// Nota mais forte na faixa (detecção livre, para afinador e notas erradas).
  ({int midi, double level, double salience})? strongest(
    Float64List mags, {
    required int lowest,
    required int highest,
    double noise = 1e-4,
    double minLevel = 1.0,
  }) {
    int? best;
    var bestLevel = 0.0;
    for (var m = lowest; m <= highest; m++) {
      final l = level(mags, m, noise: noise);
      if (l > bestLevel) {
        bestLevel = l;
        best = m;
      }
    }
    if (best == null || bestLevel < minLevel) return null;
    return (midi: best, level: bestLevel, salience: salience(mags, best, noise: noise));
  }
}

/// Detecta o ATAQUE de notas (tecla nova), para uma nota segurada não contar
/// várias vezes. Trabalha quadro a quadro com os níveis de [NoteAnalyzer].
class OnsetTracker {
  OnsetTracker({
    this.historyFrames = 6,
    this.minRise = 0.8,
    this.refractoryFrames = 5,
  });

  /// Quantos quadros anteriores formam a referência de "antes".
  final int historyFrames;

  /// Quanto o nível precisa subir (em unidades log) acima do mínimo recente.
  final double minRise;

  /// Quadros de espera depois de um ataque da mesma nota.
  final int refractoryFrames;

  final Map<int, List<double>> _history = {};
  final Map<int, int> _lastOnset = {};
  int _frame = 0;

  /// Recebe os níveis do quadro atual e o limiar absoluto por nota; retorna
  /// as notas que acabaram de ser atacadas.
  Set<int> update(Map<int, double> levels, double Function(int midi) threshold) {
    _frame++;
    final onsets = <int>{};
    for (final e in levels.entries) {
      final hist = _history.putIfAbsent(e.key, () => []);
      final recentMin = hist.isEmpty ? 0.0 : hist.reduce(math.min);
      final last = _lastOnset[e.key];
      final ready = last == null || _frame - last >= refractoryFrames;
      if (ready && e.value >= threshold(e.key) && e.value - recentMin >= minRise) {
        onsets.add(e.key);
        _lastOnset[e.key] = _frame;
        // A partir daqui a referência é o próprio ataque: só conta de novo se
        // o som cair e subir outra vez.
        hist
          ..clear()
          ..addAll(List.filled(historyFrames - 1, e.value));
      }
      hist.add(e.value);
      if (hist.length > historyFrames) hist.removeAt(0);
    }
    return onsets;
  }

  void reset() {
    _history.clear();
    _lastOnset.clear();
  }
}

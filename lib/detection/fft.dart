import 'dart:math' as math;
import 'dart:typed_data';

/// FFT radix-2 real -> magnitudes, com janela de Hann pré-calculada.
class SpectrumAnalyzer {
  SpectrumAnalyzer(this.size)
      : assert(size > 0 && (size & (size - 1)) == 0, 'tamanho deve ser potência de 2'),
        _window = Float64List(size),
        _re = Float64List(size),
        _im = Float64List(size),
        _cos = Float64List(size ~/ 2),
        _sin = Float64List(size ~/ 2),
        _rev = Int32List(size) {
    for (var i = 0; i < size; i++) {
      _window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (size - 1));
    }
    for (var i = 0; i < size ~/ 2; i++) {
      _cos[i] = math.cos(-2 * math.pi * i / size);
      _sin[i] = math.sin(-2 * math.pi * i / size);
    }
    final bits = (math.log(size) / math.ln2).round();
    for (var i = 0; i < size; i++) {
      var r = 0;
      for (var b = 0; b < bits; b++) {
        if (i & (1 << b) != 0) r |= 1 << (bits - 1 - b);
      }
      _rev[i] = r;
    }
  }

  final int size;
  final Float64List _window, _re, _im, _cos, _sin;
  final Int32List _rev;

  /// Retorna size/2 magnitudes. [samples] deve ter [size] amostras.
  Float64List magnitudes(Float64List samples) {
    for (var i = 0; i < size; i++) {
      final j = _rev[i];
      _re[j] = samples[i] * _window[i];
      _im[j] = 0;
    }
    for (var len = 2; len <= size; len <<= 1) {
      final half = len >> 1;
      final step = size ~/ len;
      for (var start = 0; start < size; start += len) {
        for (var k = 0; k < half; k++) {
          final wr = _cos[k * step], wi = _sin[k * step];
          final a = start + k, b = a + half;
          final tr = _re[b] * wr - _im[b] * wi;
          final ti = _re[b] * wi + _im[b] * wr;
          _re[b] = _re[a] - tr;
          _im[b] = _im[a] - ti;
          _re[a] += tr;
          _im[a] += ti;
        }
      }
    }
    final out = Float64List(size ~/ 2);
    final norm = 2 / size;
    for (var i = 0; i < out.length; i++) {
      out[i] = math.sqrt(_re[i] * _re[i] + _im[i] * _im[i]) * norm;
    }
    return out;
  }
}

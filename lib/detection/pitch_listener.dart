import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

import 'fft.dart';
import 'note_analyzer.dart';

/// Resumo de um quadro de áudio (para afinador e calibração).
class ListenerFrame {
  const ListenerFrame({
    required this.strongest,
    required this.strongestLevel,
    required this.rms,
    required this.medianMagnitude,
  });

  final int? strongest;
  final double strongestLevel;
  final double rms;

  /// Magnitude mediana do espectro: medida do ruído de fundo.
  final double medianMagnitude;
}

class HeardNote {
  const HeardNote(this.midi, {required this.expected});
  final int midi;

  /// true = era uma das notas esperadas; false = detecção livre (nota errada).
  final bool expected;
}

/// Escuta o microfone e reporta ataques de notas.
///
/// No jogo, [expected] informa quais notas devem soar agora; o ouvido confere
/// essas notas com prioridade (mais confiável que adivinhar do zero).
class PitchListener {
  PitchListener({
    required this.lowest,
    required this.highest,
    this.noiseFloor = 2e-4,
    this.sensitivity = 1.0,
    this.expected,
    this.reportWrongNotes = true,
  });

  static const sampleRate = 44100;
  static const fftSize = 4096;
  static const hop = 1024; // ~23 ms

  final int lowest;
  final int highest;
  double noiseFloor;
  double sensitivity;
  Set<int> Function()? expected;
  bool reportWrongNotes;

  final _notes = StreamController<HeardNote>.broadcast();
  final _frames = StreamController<ListenerFrame>.broadcast();
  Stream<HeardNote> get notes => _notes.stream;
  Stream<ListenerFrame> get frames => _frames.stream;

  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  final _fft = SpectrumAnalyzer(fftSize);
  final _analyzer = NoteAnalyzer(sampleRate: sampleRate.toDouble(), fftSize: fftSize);
  final _tracker = OnsetTracker();
  final _ring = Float64List(fftSize);
  final _window = Float64List(fftSize);
  int _write = 0;
  int _sinceFrame = 0;
  int? _carry; // byte ímpar que sobrou do pacote anterior

  double get _threshold => 2.6 / sensitivity;

  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
      autoGain: false,
      echoCancel: false,
      noiseSuppress: false,
    ));
    _sub = stream.listen(_onBytes);
    return true;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    if (await _recorder.isRecording()) await _recorder.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
    await _notes.close();
    await _frames.close();
  }

  void resetOnsets() => _tracker.reset();

  void _onBytes(Uint8List data) {
    var i = 0;
    if (_carry != null && data.isNotEmpty) {
      _push(_toSample(_carry!, data[0]));
      _carry = null;
      i = 1;
    }
    for (; i + 1 < data.length; i += 2) {
      _push(_toSample(data[i], data[i + 1]));
    }
    if (i < data.length) _carry = data[i];
  }

  static double _toSample(int lo, int hi) {
    var v = lo | (hi << 8);
    if (v >= 0x8000) v -= 0x10000;
    return v / 32768.0;
  }

  void _push(double s) {
    _ring[_write] = s;
    _write = (_write + 1) % fftSize;
    if (++_sinceFrame >= hop) {
      _sinceFrame = 0;
      _processFrame();
    }
  }

  void _processFrame() {
    var sumSq = 0.0;
    for (var k = 0; k < fftSize; k++) {
      final v = _ring[(_write + k) % fftSize];
      _window[k] = v;
      sumSq += v * v;
    }
    final mags = _fft.magnitudes(_window);
    final noise = math.max(noiseFloor, 1e-6);

    final range = [for (var m = lowest; m <= highest; m++) m];
    final levels = _analyzer.levels(mags, range, noise: noise);
    final onsets = _tracker.update(levels, (_) => _threshold);

    final exp = expected?.call() ?? const <int>{};
    final hitExpected = onsets.where(exp.contains).toSet();
    for (final m in hitExpected) {
      _notes.add(HeardNote(m, expected: true));
    }

    if (reportWrongNotes && hitExpected.isEmpty && onsets.isNotEmpty) {
      final wrong = _pickWrongNote(mags, onsets, levels, noise);
      if (wrong != null) _notes.add(HeardNote(wrong, expected: exp.contains(wrong)));
    }

    // Quadro para afinador/calibração.
    int? best;
    var bestLevel = 0.0;
    levels.forEach((m, l) {
      if (l > bestLevel) {
        bestLevel = l;
        best = m;
      }
    });
    final sorted = Float64List.fromList(mags.sublist(2, 1500))..sort();
    _frames.add(ListenerFrame(
      strongest: bestLevel >= _threshold ? best : null,
      strongestLevel: bestLevel,
      rms: math.sqrt(sumSq / fftSize),
      medianMagnitude: sorted[sorted.length ~/ 2],
    ));
  }

  /// Entre os ataques do quadro, escolhe a nota mais provável (ignora
  /// harmônicos de outra nota que também atacou).
  int? _pickWrongNote(
      Float64List mags, Set<int> onsets, Map<int, double> levels, double noise) {
    final candidates = onsets.toList()..sort();
    for (final m in candidates) {
      final isHarmonic = candidates.any((o) => o < m && const {12, 19, 24, 28, 31}.contains(m - o));
      if (isHarmonic) continue;
      if (levels[m]! < _threshold + 0.4) continue;
      if (_analyzer.salience(mags, m, noise: noise) < 1.15) continue;
      return m;
    }
    return null;
  }
}

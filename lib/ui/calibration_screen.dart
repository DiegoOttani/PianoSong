import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/note.dart';
import '../detection/pitch_listener.dart';
import '../services/app_services.dart';

enum _Step { intro, silence, notes, latency, done }

/// Calibração: ruído do ambiente, teste de notas e atraso do microfone.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  _Step _step = _Step.intro;
  PitchListener? _listener;
  final _subs = <StreamSubscription<dynamic>>[];
  String? _error;
  String _status = '';

  // Teste de notas
  static const _testNotes = [48, 60, 72];
  int _noteIndex = 0;
  Timer? _noteTimer;

  // Latência
  static const _flashCount = 8;
  static const _flashIntervalMs = 1000;
  final _flashTimes = <int>[];
  final _delays = <int>[];
  final _clock = Stopwatch();
  bool _flashOn = false;
  int _countIn = 0;

  @override
  void dispose() {
    _noteTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _listener?.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    final s = AppServices.of(context).settings;
    final l = PitchListener(
      lowest: s.keyboard.lowest,
      highest: s.keyboard.highest,
      noiseFloor: s.noiseFloor,
      sensitivity: s.sensitivity,
      reportWrongNotes: false,
    );
    if (!await l.start()) {
      setState(() => _error = 'Sem permissão de microfone. Libere nas configurações do Android.');
      return;
    }
    _listener = l;
    _measureSilence();
  }

  void _measureSilence() {
    setState(() {
      _step = _Step.silence;
      _status = 'Fique em silêncio por 3 segundos…';
    });
    final samples = <double>[];
    late StreamSubscription<ListenerFrame> sub;
    sub = _listener!.frames.listen((f) {
      samples.add(f.medianMagnitude);
      if (samples.length >= 130) {
        sub.cancel();
        samples.sort();
        final noise = samples[samples.length ~/ 2].clamp(1e-6, 0.05);
        if (!mounted) return;
        final s = AppServices.of(context).settings;
        s.noiseFloor = noise;
        _listener!.noiseFloor = noise;
        _listener!.resetOnsets();
        _startNotes();
      }
    });
    _subs.add(sub);
  }

  void _startNotes() {
    _noteIndex = 0;
    setState(() => _step = _Step.notes);
    late StreamSubscription<HeardNote> sub;
    sub = _listener!.notes.listen((h) {
      if (_step != _Step.notes || h.midi != _testNotes[_noteIndex]) return;
      _nextNote();
    });
    _subs.add(sub);
    _listener!.expected = () => _step == _Step.notes ? {_testNotes[_noteIndex]} : const {};
    _armNoteTimer();
  }

  void _armNoteTimer() {
    _noteTimer?.cancel();
    _status = '';
    _noteTimer = Timer(const Duration(seconds: 8), () {
      // Não ouviu: aumenta a sensibilidade e tenta de novo.
      final s = AppServices.of(context).settings;
      if (s.sensitivity < 2.0) {
        s.sensitivity = (s.sensitivity + 0.25).clamp(0.5, 2.0);
        _listener!.sensitivity = s.sensitivity;
      }
      setState(() => _status =
          'Não ouvi. Aumentei a sensibilidade para ${(s.sensitivity * 100).round()}%. Toque de novo, com firmeza.');
      _armNoteTimer();
    });
  }

  void _nextNote() {
    _noteTimer?.cancel();
    if (_noteIndex + 1 < _testNotes.length) {
      setState(() {
        _noteIndex++;
        _status = 'Ouvi!';
      });
      _armNoteTimer();
    } else {
      _startLatency();
    }
  }

  void _startLatency() {
    setState(() {
      _step = _Step.latency;
      _status = '';
    });
    _delays.clear();
    _flashTimes.clear();
    _listener!.expected = () => {
          for (var m = _listener!.lowest; m <= _listener!.highest; m++) m,
        };
    late StreamSubscription<HeardNote> sub;
    sub = _listener!.notes.listen((h) {
      if (_step != _Step.latency || _flashTimes.isEmpty) return;
      final now = _clock.elapsedMilliseconds;
      // Flash mais próximo (o som pode chegar antes do próximo flash).
      final nearest = _flashTimes.reduce((a, b) => (a - now).abs() <= (b - now).abs() ? a : b);
      final d = now - nearest;
      if (d > -150 && d < 500 && _delays.length < _flashTimes.length) _delays.add(d);
    });
    _subs.add(sub);
    _runFlashes();
  }

  Future<void> _runFlashes() async {
    _clock
      ..reset()
      ..start();
    for (_countIn = 3; _countIn > 0; _countIn--) {
      setState(() {});
      await Future<void>.delayed(const Duration(milliseconds: _flashIntervalMs));
      if (!mounted) return;
    }
    final start = _clock.elapsedMilliseconds;
    for (var i = 0; i < _flashCount; i++) {
      final target = start + i * _flashIntervalMs;
      final wait = target - _clock.elapsedMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      if (!mounted) return;
      _flashTimes.add(_clock.elapsedMilliseconds);
      setState(() => _flashOn = true);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      setState(() => _flashOn = false);
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    _finishLatency();
  }

  void _finishLatency() {
    if (_delays.length < 4) {
      setState(() => _status =
          'Só ouvi ${_delays.length} de $_flashCount toques. Vamos tentar de novo.');
      _startLatency();
      return;
    }
    final sorted = [..._delays]..sort();
    final median = sorted[sorted.length ~/ 2].clamp(0, 400);
    final s = AppServices.of(context).settings;
    s.latencyMs = median;
    s.calibrated = true;
    _listener?.stop();
    setState(() => _step = _Step.done);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppServices.of(context).settings;
    final naming = s.naming == NoteNaming.none ? NoteNaming.solfege : s.naming;
    return Scaffold(
      appBar: AppBar(title: const Text('Calibração')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _error != null ? Text(_error!) : _content(naming, s.latencyMs),
          ),
        ),
      ),
    );
  }

  Widget _content(NoteNaming naming, int latency) {
    final big = Theme.of(context).textTheme.headlineMedium;
    switch (_step) {
      case _Step.intro:
        return Column(
          children: [
            const Text(
              'Coloque o celular perto do teclado (em cima dele ou na estante de partitura), '
              'com o volume do teclado num nível confortável. A calibração tem 3 partes: '
              'silêncio, 3 notas de teste e tocar junto com uma luz.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _begin, child: const Text('Começar')),
          ],
        );
      case _Step.silence:
        return Column(children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(_status),
        ]);
      case _Step.notes:
        return Column(children: [
          Text('Parte 2 de 3 · nota ${_noteIndex + 1} de ${_testNotes.length}'),
          const SizedBox(height: 16),
          const Text('Toque esta nota:'),
          Text(Note.name(_testNotes[_noteIndex], naming, withOctave: true), style: big),
          const Text('(Dó4 é o Dó central do teclado)', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 16),
          Text(_status, textAlign: TextAlign.center),
        ]);
      case _Step.latency:
        return Column(children: [
          const Text('Parte 3 de 3'),
          const SizedBox(height: 8),
          const Text(
            'Toque qualquer tecla exatamente quando a luz acender (8 vezes, no ritmo).',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _flashOn ? Colors.amber : Colors.white10,
            ),
            alignment: Alignment.center,
            child: Text(_countIn > 0 ? '$_countIn' : '', style: big),
          ),
          const SizedBox(height: 16),
          Text('Toques ouvidos: ${_delays.length}'),
          if (_status.isNotEmpty) Text(_status, textAlign: TextAlign.center),
        ]);
      case _Step.done:
        return Column(children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 64),
          const SizedBox(height: 12),
          Text('Pronto! Atraso medido: $latency ms', style: big, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('Você pode ajustar a sensibilidade e o atraso nas configurações.',
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Concluir')),
        ]);
    }
  }
}

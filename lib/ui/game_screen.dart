import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/keyboard_layout.dart';
import '../core/note.dart';
import '../detection/pitch_listener.dart';
import '../game/falling_notes_painter.dart';
import '../game/game_engine.dart';
import '../library/song_repository.dart';
import '../services/app_services.dart';
import '../services/settings.dart';
import '../song/difficulty_generator.dart';
import 'results_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.entry,
    required this.config,
    required this.difficulty,
    required this.inputMode,
  });

  final SongEntry entry;
  final GameConfig config;
  final Difficulty difficulty;
  final InputMode inputMode;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late GameEngine _engine;
  late final Ticker _ticker;
  final _repaint = ValueNotifier<int>(0);
  final _flashes = <int, KeyFlash>{};
  final _clock = Stopwatch()..start();
  Duration _lastElapsed = Duration.zero;
  bool _paused = false;
  bool _finishedHandled = false;
  PitchListener? _listener;
  StreamSubscription<HeardNote>? _heardSub;
  String? _micError;
  int _lastBarVibrated = -1;

  Settings get _settings => AppServices.of(context).settings;
  KeyboardSize get _keyboard => _settings.keyboard;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _engine = GameEngine(widget.config);
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startMic());
  }

  Future<void> _startMic() async {
    if (widget.inputMode != InputMode.microphone) return;
    final s = _settings;
    final listener = PitchListener(
      lowest: _keyboard.lowest,
      highest: _keyboard.highest,
      noiseFloor: s.noiseFloor,
      sensitivity: s.sensitivity,
      expected: () => _paused ? const {} : _engine.expectedPitches(),
    );
    final ok = await listener.start();
    if (!mounted) {
      await listener.dispose();
      return;
    }
    if (!ok) {
      setState(() => _micError = 'Sem permissão de microfone. Use o toque na tela ou libere nas configurações do Android.');
      return;
    }
    _listener = listener;
    _heardSub = listener.notes.listen((h) {
      if (!_paused) _play(h.midi);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _heardSub?.cancel();
    _listener?.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  double _now() => _clock.elapsedMicroseconds / 1000.0;

  void _onTick(Duration elapsed) {
    final delta = (elapsed - _lastElapsed).inMicroseconds / 1000.0;
    _lastElapsed = elapsed;
    if (_paused || _engine.finished) return;
    _engine.tick(delta.clamp(0, 100));
    _consumeEvents();
    _maybeVibrate();
    _repaint.value++;
    if (_engine.finished && !_finishedHandled) {
      _finishedHandled = true;
      _finish();
    }
  }

  void _maybeVibrate() {
    if (!_settings.vibrateOnBar) return;
    final bars = _engine.config.song.barsMs;
    for (var i = _lastBarVibrated + 1; i < bars.length; i++) {
      if (bars[i] > _engine.songTimeMs) break;
      _lastBarVibrated = i;
      if (_engine.songTimeMs - bars[i] < 100) HapticFeedback.lightImpact();
    }
  }

  void _play(int midi) {
    _engine.notePlayed(midi);
    _consumeEvents();
  }

  void _consumeEvents() {
    final now = _now();
    for (final e in _engine.drainEvents()) {
      switch (e.type) {
        case GameEventType.hit:
          _flashes[e.pitch!] = KeyFlash(
              GameColors.judgement(e.judgement!), now, label: e.judgement!.label);
        case GameEventType.wrong:
          _flashes[e.pitch!] = KeyFlash(GameColors.wrong, now,
              label: Note.name(e.pitch!, _settings.naming == NoteNaming.none
                  ? NoteNaming.solfege
                  : _settings.naming));
        case GameEventType.miss:
          break;
        case GameEventType.loopRestart:
          _listener?.resetOnsets();
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _finish() async {
    final repo = AppServices.of(context).repository;
    await _listener?.stop();
    final s = _engine.score;
    final result = SessionResult(
      songId: widget.entry.id,
      difficulty: widget.difficulty,
      score: s.score,
      accuracy: s.accuracy,
      stars: s.stars,
      maxCombo: s.maxCombo,
      speed: _engine.speed,
      at: DateTime.now(),
    );
    final previousBest = repo.bestStars(widget.entry.id, widget.difficulty);
    await repo.addResult(result);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ResultsScreen(
        entry: widget.entry,
        difficulty: widget.difficulty,
        score: s,
        speed: _engine.speed,
        previousBestStars: previousBest,
        playAgain: () => GameScreen(
          entry: widget.entry,
          config: widget.config,
          difficulty: widget.difficulty,
          inputMode: widget.inputMode,
        ),
      ),
    ));
  }

  void _onPointerDown(PointerDownEvent e, BoxConstraints c) {
    final kbTop = c.maxHeight * (1 - FallingNotesPainter.keyboardFraction);
    if (e.localPosition.dy < kbTop) return;
    final geo = KeyboardGeometry(_keyboard, c.maxWidth);
    final blackBottom = kbTop + c.maxHeight * FallingNotesPainter.keyboardFraction * 0.62;
    final midi = geo.keyAt(e.localPosition.dx, preferBlack: e.localPosition.dy < blackBottom);
    if (midi == null) return;
    _flashes.putIfAbsent(midi, () => KeyFlash(Colors.white38, _now()));
    _play(midi);
  }

  Future<void> _pause() async {
    setState(() => _paused = true);
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Pausado'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'exit'), child: const Text('Sair')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'restart'), child: const Text('Reiniciar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'resume'), child: const Text('Continuar')),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'exit':
        Navigator.of(context).pop();
      case 'restart':
        setState(() {
          _engine = GameEngine(widget.config);
          _flashes.clear();
          _lastBarVibrated = -1;
          _listener?.resetOnsets();
          _paused = false;
        });
      default:
        setState(() => _paused = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _engine.score;
    final firstStart = _engine.config.hasLoop
        ? _engine.config.loopStartMs!
        : (_engine.notes.isEmpty ? 0 : _engine.notes.first.note.startMs);
    final countdown = firstStart - _engine.songTimeMs;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_paused) _pause();
      },
      child: Scaffold(
        backgroundColor: GameColors.background,
        body: LayoutBuilder(
          builder: (context, c) => Stack(
            children: [
              Listener(
                onPointerDown: (e) => _onPointerDown(e, c),
                child: CustomPaint(
                  size: Size(c.maxWidth, c.maxHeight),
                  painter: FallingNotesPainter(
                    engine: _engine,
                    keyboard: _keyboard,
                    naming: _settings.naming,
                    flashes: _flashes,
                    nowMs: _now,
                    beatFlash: _settings.beatFlash,
                    repaint: _repaint,
                  ),
                ),
              ),
              // HUD
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Row(
                  children: [
                    IconButton.filledTonal(
                        onPressed: _pause, icon: const Icon(Icons.pause), iconSize: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.entry.title} · ${widget.difficulty.label} · ${(_engine.speed * 100).round()}%'
                            '${_engine.config.hasLoop ? ' · loop ${_engine.loopCount + 1}' : ''}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(value: _engine.progress, minHeight: 3),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    _Stat('Pontos', '${s.score}'),
                    _Stat('Combo', '${s.combo}x${s.multiplier > 1 ? ' (×${s.multiplier})' : ''}'),
                    _Stat('Precisão', s.judged == 0 ? '–' : '${(s.accuracy * 100).round()}%'),
                    if (widget.inputMode == InputMode.microphone)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(_listener != null ? Icons.mic : Icons.mic_off,
                            color: _listener != null ? Colors.greenAccent : Colors.redAccent,
                            size: 20),
                      ),
                  ],
                ),
              ),
              if (_engine.waiting)
                Positioned(
                  top: 64,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _Pill(
                      'Toque: ${_engine.expectedPitches().map((m) => Note.name(m, _settings.naming == NoteNaming.none ? NoteNaming.solfege : _settings.naming, withOctave: true)).join(' + ')}',
                    ),
                  ),
                ),
              if (countdown > 0 && !_paused)
                Center(
                  child: Text(
                    '${(countdown / 1000 / _engine.speed).ceil()}',
                    style: const TextStyle(
                        fontSize: 72, color: Colors.white24, fontWeight: FontWeight.bold),
                  ),
                ),
              if (_micError != null)
                Positioned(
                  top: 64,
                  left: 24,
                  right: 24,
                  child: Material(
                    color: Colors.red.shade900,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_micError!, style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orangeAccent.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      );
}

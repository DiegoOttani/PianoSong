import 'dart:math' as math;

import '../song/song_model.dart';
import 'scoring.dart';

class GameConfig {
  const GameConfig({
    required this.song,
    this.speed = 1.0,
    this.waitMode = false,
    this.hands = const {Hand.right, Hand.left},
    this.loopStartMs,
    this.loopEndMs,
    this.windows = const HitWindows(),
    this.latencyMs = 0,
    this.speedUpOnCleanLoop = false,
    this.leadInMs = 2000,
  });

  final Song song;
  final double speed;
  final bool waitMode;

  /// Mãos cobradas. As outras aparecem em cinza e não contam.
  final Set<Hand> hands;
  final int? loopStartMs;
  final int? loopEndMs;
  final HitWindows windows;

  /// Atraso entre tocar e o app perceber (calibrado), em ms reais.
  final int latencyMs;
  final bool speedUpOnCleanLoop;

  /// Tempo antes da primeira nota (contagem), em ms da música.
  final int leadInMs;

  bool get hasLoop => loopStartMs != null && loopEndMs != null && loopEndMs! > loopStartMs!;
}

class PlayNote {
  PlayNote(this.note, this.active);
  final NoteEvent note;

  /// Se a nota é cobrada (mão escolhida e dentro do loop).
  final bool active;
  Judgement? judgement;

  bool get pending => active && judgement == null;
}

enum GameEventType { hit, miss, wrong, loopRestart }

class GameEvent {
  const GameEvent(this.type, {this.pitch, this.judgement, this.hand});
  final GameEventType type;
  final int? pitch;
  final Judgement? judgement;
  final Hand? hand;
}

/// Lógica do jogo, independente de tela e de áudio.
class GameEngine {
  GameEngine(this.config) : speed = config.speed {
    final loopStart = config.loopStartMs ?? 0;
    final loopEnd = config.loopEndMs ?? 1 << 40;
    notes = [
      for (final n in config.song.notes)
        PlayNote(
          n,
          config.hands.contains(n.hand) &&
              (!config.hasLoop || (n.startMs >= loopStart && n.startMs < loopEnd)),
        ),
    ];
    final firstNote = config.hasLoop
        ? loopStart
        : (config.song.notes.isEmpty ? 0 : config.song.notes.first.startMs);
    songTimeMs = (firstNote - config.leadInMs).toDouble();
    _endMs = config.song.durationMs + 1500;
  }

  final GameConfig config;
  late final List<PlayNote> notes;
  final ScoreState score = ScoreState();
  final List<GameEvent> _events = [];

  double songTimeMs = 0;
  double speed;
  bool waiting = false;
  bool finished = false;
  int loopCount = 0;
  int _missesThisPass = 0;
  int _first = 0; // primeira nota possivelmente pendente
  late final int _endMs;

  HitWindows get _w => config.windows;

  /// Tempo da música em que o som que acabou de chegar foi tocado.
  double get _inputTime =>
      waiting ? songTimeMs : songTimeMs - config.latencyMs * speed;

  void tick(double realDeltaMs) {
    if (finished) return;
    var next = songTimeMs + realDeltaMs * speed;

    if (config.waitMode) {
      final chordStart = _nextPendingStart();
      if (chordStart != null && next >= chordStart) {
        next = chordStart.toDouble();
        waiting = true;
      } else {
        waiting = false;
      }
    }
    songTimeMs = next;

    if (!config.waitMode) _markMisses();

    if (config.hasLoop && songTimeMs >= config.loopEndMs!) {
      _restartLoop();
    } else if (!config.hasLoop && songTimeMs >= _endMs) {
      finished = true;
    }
  }

  /// Chame quando uma tecla for detectada (microfone ou toque na tela).
  void notePlayed(int pitch) {
    if (finished) return;
    final t = _inputTime;
    PlayNote? best;
    var bestDelta = double.infinity;

    final waitChord = waiting ? _nextPendingStart() : null;
    for (var i = _first; i < notes.length; i++) {
      final p = notes[i];
      if (p.note.startMs > t + _w.goodMs) break;
      if (!p.pending || p.note.pitch != pitch) continue;
      final inWaitChord = waitChord != null && (p.note.startMs - waitChord).abs() <= 40;
      final delta = inWaitChord ? 0.0 : (p.note.startMs - t).toDouble();
      if (delta.abs() <= _w.goodMs && delta.abs() < bestDelta) {
        best = p;
        bestDelta = delta.abs();
      }
    }

    if (best == null) {
      score.wrong++;
      _events.add(GameEvent(GameEventType.wrong, pitch: pitch));
      return;
    }
    final j = config.waitMode ? Judgement.perfect : _w.judge(bestDelta)!;
    best.judgement = j;
    score.register(j);
    _events.add(GameEvent(GameEventType.hit, pitch: pitch, judgement: j, hand: best.note.hand));
    _advanceFirst();
    if (waiting && _nextPendingStart() != waitChord) waiting = false;
  }

  /// Notas que o detector deve procurar agora (pendentes perto do tempo atual).
  Set<int> expectedPitches({int lookaheadMs = 0}) {
    final t = _inputTime;
    final waitChord = waiting ? _nextPendingStart() : null;
    final out = <int>{};
    for (var i = _first; i < notes.length; i++) {
      final p = notes[i];
      if (p.note.startMs > t + _w.goodMs + lookaheadMs && waitChord == null) break;
      if (!p.pending) continue;
      if (waitChord != null) {
        if ((p.note.startMs - waitChord).abs() <= 40) out.add(p.note.pitch);
        if (p.note.startMs > waitChord + 40) break;
      } else if ((p.note.startMs - t).abs() <= _w.goodMs + lookaheadMs) {
        out.add(p.note.pitch);
      }
    }
    return out;
  }

  List<GameEvent> drainEvents() {
    final e = List<GameEvent>.of(_events);
    _events.clear();
    return e;
  }

  int get totalActive => notes.where((n) => n.active).length;

  double get progress {
    final start = config.hasLoop ? config.loopStartMs! : 0;
    final end = config.hasLoop ? config.loopEndMs! : config.song.durationMs;
    if (end <= start) return 1;
    return ((songTimeMs - start) / (end - start)).clamp(0.0, 1.0);
  }

  int? _nextPendingStart() {
    for (var i = _first; i < notes.length; i++) {
      if (notes[i].pending) return notes[i].note.startMs;
    }
    return null;
  }

  void _markMisses() {
    final t = _inputTime;
    for (var i = _first; i < notes.length; i++) {
      final p = notes[i];
      if (p.note.startMs + _w.goodMs >= t) break;
      if (p.pending) {
        p.judgement = Judgement.miss;
        score.register(Judgement.miss);
        _missesThisPass++;
        _events.add(GameEvent(GameEventType.miss, pitch: p.note.pitch, hand: p.note.hand));
      }
    }
    _advanceFirst();
  }

  void _advanceFirst() {
    while (_first < notes.length &&
        (!notes[_first].active || notes[_first].judgement != null) &&
        notes[_first].note.startMs + _w.goodMs < _inputTime) {
      _first++;
    }
  }

  void _restartLoop() {
    // Notas do loop que ficaram sem resposta contam como erro.
    for (final p in notes) {
      if (p.pending) {
        p.judgement = Judgement.miss;
        score.register(Judgement.miss);
        _missesThisPass++;
      }
    }
    final clean = _missesThisPass == 0;
    loopCount++;
    if (clean && config.speedUpOnCleanLoop) speed = math.min(speed + 0.05, 1.2);
    for (final p in notes) {
      if (p.active) p.judgement = null;
    }
    _missesThisPass = 0;
    _first = 0;
    waiting = false;
    songTimeMs = (config.loopStartMs! - 1000).toDouble();
    _events.add(const GameEvent(GameEventType.loopRestart));
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_song/game/game_engine.dart';
import 'package:piano_song/game/scoring.dart';
import 'package:piano_song/song/song_model.dart';

NoteEvent n(int pitch, int start, {Hand hand = Hand.right}) =>
    NoteEvent(pitch: pitch, startMs: start, durationMs: 300, hand: hand);

Song song() => Song(title: 't', notes: [
      n(60, 1000),
      n(62, 2000),
      n(48, 2000, hand: Hand.left),
      n(64, 3000),
    ]);

/// Avança o relógio até [ms] da música em passos de 10 ms reais.
void runTo(GameEngine e, double ms) {
  for (var i = 0; i < 100000 && e.songTimeMs < ms && !e.finished; i++) {
    e.tick(10);
    if (e.waiting) return;
  }
}

void main() {
  test('pontuação, combo e estrelas', () {
    final s = ScoreState();
    for (var i = 0; i < 12; i++) {
      s.register(Judgement.perfect);
    }
    expect(s.combo, 12);
    expect(s.multiplier, 2);
    expect(s.score, 100 * 10 + 200 * 2);
    s.register(Judgement.miss);
    expect(s.combo, 0);
    expect(s.maxCombo, 12);
    expect(ScoreState.starsFor(0.96), 3);
    expect(ScoreState.starsFor(0.86), 2);
    expect(ScoreState.starsFor(0.5), 0);
  });

  test('acerto perfeito, bom e erro por tempo', () {
    final e = GameEngine(GameConfig(song: song(), leadInMs: 1000));
    expect(e.songTimeMs, 0);
    runTo(e, 1050);
    e.notePlayed(60); // 50 ms atrasado -> perfeito
    runTo(e, 2150);
    e.notePlayed(62); // 150 ms atrasado -> bom
    runTo(e, 3500); // 48 e 64 passam sem tocar
    final events = e.drainEvents();
    expect(events.where((x) => x.type == GameEventType.hit).map((x) => x.judgement),
        [Judgement.perfect, Judgement.good]);
    expect(e.score.miss, 2);
    runTo(e, 99999);
    expect(e.finished, isTrue);
  });

  test('nota errada não conta como acerto', () {
    final e = GameEngine(GameConfig(song: song(), leadInMs: 1000));
    runTo(e, 1000);
    e.notePlayed(61);
    expect(e.score.wrong, 1);
    expect(e.score.perfect, 0);
  });

  test('latência é descontada', () {
    final e = GameEngine(GameConfig(song: song(), leadInMs: 1000, latencyMs: 150));
    runTo(e, 1150); // o som chegou 150 ms depois de tocar no tempo certo
    e.notePlayed(60);
    expect(e.score.perfect, 1);
  });

  test('modo espera para o relógio até tocar o acorde', () {
    final e = GameEngine(GameConfig(song: song(), leadInMs: 1000, waitMode: true));
    runTo(e, 5000);
    expect(e.waiting, isTrue);
    expect(e.songTimeMs, 1000);
    for (var i = 0; i < 100; i++) {
      e.tick(10);
    }
    expect(e.songTimeMs, 1000, reason: 'continua parado');
    expect(e.expectedPitches(), {60});
    e.notePlayed(60);
    runTo(e, 5000);
    expect(e.songTimeMs, 2000);
    expect(e.expectedPitches(), {62, 48});
    e.notePlayed(48);
    expect(e.waiting, isTrue, reason: 'ainda falta o 62');
    e.notePlayed(62);
    expect(e.waiting, isFalse);
    expect(e.score.miss, 0);
  });

  test('mãos separadas: só a mão escolhida é cobrada', () {
    final e = GameEngine(GameConfig(song: song(), leadInMs: 1000, hands: {Hand.left}));
    expect(e.totalActive, 1);
    runTo(e, 99999);
    expect(e.score.miss, 1);
  });

  test('loop reinicia e acelera quando limpo', () {
    final e = GameEngine(GameConfig(
      song: song(),
      loopStartMs: 2000,
      loopEndMs: 2500,
      hands: {Hand.right},
      speedUpOnCleanLoop: true,
      leadInMs: 1000,
    ));
    expect(e.totalActive, 1); // só o 62
    runTo(e, 2000);
    e.notePlayed(62);
    for (var i = 0; i < 1000 && e.loopCount == 0; i++) {
      e.tick(10);
    }
    expect(e.loopCount, 1);
    expect(e.speed, closeTo(1.05, 1e-9));
    expect(e.songTimeMs, lessThan(2000));
    expect(e.notes.where((p) => p.pending).length, 1, reason: 'nota liberada de novo');
  });
}

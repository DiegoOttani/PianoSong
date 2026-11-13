import 'dart:math' as math;

enum Judgement {
  perfect('Perfeito', 100),
  good('Bom', 60),
  miss('Errou', 0);

  const Judgement(this.label, this.points);
  final String label;
  final int points;
}

class HitWindows {
  const HitWindows({this.perfectMs = 90, this.goodMs = 180});
  final int perfectMs;
  final int goodMs;

  Judgement? judge(double deltaMs) {
    final d = deltaMs.abs();
    if (d <= perfectMs) return Judgement.perfect;
    if (d <= goodMs) return Judgement.good;
    return null;
  }
}

class ScoreState {
  int score = 0;
  int combo = 0;
  int maxCombo = 0;
  int perfect = 0;
  int good = 0;
  int miss = 0;

  /// Notas tocadas que não estavam na música (só informativo).
  int wrong = 0;

  int get judged => perfect + good + miss;

  double get accuracy => judged == 0 ? 0 : (perfect + good * 0.6) / judged;

  int get multiplier => 1 + math.min(combo ~/ 10, 3);

  static int starsFor(double accuracy) => accuracy >= 0.95
      ? 3
      : accuracy >= 0.85
          ? 2
          : accuracy >= 0.70
              ? 1
              : 0;

  int get stars => starsFor(accuracy);

  void register(Judgement j) {
    switch (j) {
      case Judgement.perfect:
        perfect++;
      case Judgement.good:
        good++;
      case Judgement.miss:
        miss++;
    }
    if (j == Judgement.miss) {
      combo = 0;
    } else {
      score += j.points * multiplier;
      combo++;
      maxCombo = math.max(maxCombo, combo);
    }
  }
}

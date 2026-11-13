import 'package:material_ui/material_ui.dart';

import '../game/scoring.dart';
import '../library/song_repository.dart';
import '../services/app_services.dart';
import '../song/difficulty_generator.dart';
import 'widgets.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({
    super.key,
    required this.entry,
    required this.difficulty,
    required this.score,
    required this.speed,
    required this.previousBestStars,
    required this.playAgain,
  });

  final SongEntry entry;
  final Difficulty difficulty;
  final ScoreState score;
  final double speed;
  final int previousBestStars;
  final Widget Function() playAgain;

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final next = difficulty.index + 1 < Difficulty.values.length
        ? Difficulty.values[difficulty.index + 1]
        : null;
    final unlockedNow = next != null &&
        score.stars >= 3 &&
        previousBestStars < 3 &&
        !services.settings.unlockAll;
    final newRecord = score.score > 0 &&
        services.repository
                .resultsFor(entry.id, difficulty)
                .where((r) => r.score >= score.score)
                .length ==
            1;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  Text(entry.title,
                      style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                  Text('${difficulty.label} · ${(speed * 100).round()}%'),
                  const SizedBox(height: 16),
                  Stars(score.stars, size: 48),
                  const SizedBox(height: 8),
                  Text('${(score.accuracy * 100).toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.displaySmall),
                  Text('${score.score} pontos · combo máximo ${score.maxCombo}'),
                  if (newRecord)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Chip(label: Text('Novo recorde!'), avatar: Icon(Icons.emoji_events)),
                    ),
                  if (unlockedNow)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Chip(
                          label: Text('Nível ${next.label} liberado!'),
                          avatar: const Icon(Icons.lock_open)),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    children: [
                      _count('Perfeito', score.perfect, Colors.amber),
                      _count('Bom', score.good, Colors.tealAccent),
                      _count('Errou', score.miss, Colors.redAccent),
                      _count('Notas a mais', score.wrong, Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Voltar'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context)
                            .pushReplacement(MaterialPageRoute(builder: (_) => playAgain())),
                        icon: const Icon(Icons.replay),
                        label: const Text('Tocar de novo'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _count(String label, int value, Color color) => Column(
        children: [
          Text('$value', style: TextStyle(fontSize: 22, color: color, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
}

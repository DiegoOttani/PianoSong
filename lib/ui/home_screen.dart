import 'package:material_ui/material_ui.dart';

import '../library/song_repository.dart';
import '../services/app_services.dart';
import '../song/difficulty_generator.dart';
import 'calibration_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'song_detail_screen.dart';
import 'tuner_screen.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final repo = services.repository;
    final streak = repo.streakDays;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PianoSong'),
        actions: [
          if (streak > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                avatar: const Icon(Icons.local_fire_department, color: Colors.orange, size: 18),
                label: Text('$streak ${streak == 1 ? 'dia' : 'dias'}'),
              ),
            ),
          IconButton(
            tooltip: 'Afinador / teste do microfone',
            icon: const Icon(Icons.graphic_eq),
            onPressed: () => _open(const TunerScreen()),
          ),
          IconButton(
            tooltip: 'Configurações',
            icon: const Icon(Icons.settings),
            onPressed: () => _open(const SettingsScreen()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const SearchScreen()),
        icon: const Icon(Icons.search),
        label: const Text('Buscar músicas'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (!services.settings.calibrated)
            Card(
              margin: const EdgeInsets.all(12),
              child: ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Calibre o microfone'),
                subtitle: const Text(
                    'Leva 30 segundos: mede o ruído do ambiente e o atraso do microfone para o app ouvir o teclado direito.'),
                trailing: FilledButton(
                  onPressed: () => _open(const CalibrationScreen()),
                  child: const Text('Calibrar'),
                ),
              ),
            ),
          for (final e in repo.entries) _songTile(e, repo),
        ],
      ),
    );
  }

  Widget _songTile(SongEntry e, SongRepository repo) {
    final stars = [for (final d in Difficulty.values) repo.bestStars(e.id, d)];
    return ListTile(
      leading: CircleAvatar(
        child: Icon(e.isDemo ? Icons.music_note : Icons.library_music),
      ),
      title: Text(e.title),
      subtitle: Row(
        children: [
          for (var i = 0; i < Difficulty.values.length; i++) ...[
            Text(Difficulty.values[i].label.substring(0, 3),
                style: const TextStyle(fontSize: 11)),
            Stars(stars[i], size: 12),
            const SizedBox(width: 6),
          ],
        ],
      ),
      onTap: () => _open(SongDetailScreen(entry: e)),
    );
  }
}

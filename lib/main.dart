import 'package:material_ui/material_ui.dart';

import 'library/bitmidi_api.dart';
import 'library/song_repository.dart';
import 'services/app_services.dart';
import 'services/settings.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  final repository = await SongRepository.open();
  runApp(AppServices(
    settings: settings,
    repository: repository,
    bitMidi: BitMidiApi(),
    child: const PianoSongApp(),
  ));
}

class PianoSongApp extends StatelessWidget {
  const PianoSongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PianoSong',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4FC3F7),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

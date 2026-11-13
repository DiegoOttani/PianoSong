import 'package:material_ui/material_ui.dart';

import '../core/keyboard_layout.dart';
import '../core/note.dart';
import '../services/app_services.dart';
import 'calibration_screen.dart';
import 'tuner_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppServices.of(context).settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _header(context, 'Teclado'),
            ListTile(
              title: const Text('Tamanho do teclado'),
              subtitle: Text(
                  '${Note.name(s.keyboard.lowest, NoteNaming.solfege, withOctave: true)} até '
                  '${Note.name(s.keyboard.highest, NoteNaming.solfege, withOctave: true)}'),
              trailing: DropdownButton<KeyboardSize>(
                value: s.keyboard,
                items: [
                  for (final k in KeyboardSize.values)
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: (v) => s.keyboard = v!,
              ),
            ),
            ListTile(
              title: const Text('Nome das notas'),
              subtitle: SegmentedButton<NoteNaming>(
                segments: [
                  for (final n in NoteNaming.values) ButtonSegment(value: n, label: Text(n.label)),
                ],
                selected: {s.naming},
                onSelectionChanged: (v) => s.naming = v.first,
              ),
            ),
            _header(context, 'Som'),
            ListTile(
              title: Text('Volume do piano: ${(s.volume * 100).round()}%'),
              subtitle: Slider(
                value: s.volume,
                min: 0,
                max: 1,
                divisions: 20,
                onChanged: (v) => s.volume = v,
              ),
            ),
            SwitchListTile(
              title: const Text('Som nas teclas da tela'),
              value: s.keySound,
              onChanged: (v) => s.keySound = v,
            ),
            SwitchListTile(
              title: const Text('Tocar a outra mão sozinho'),
              subtitle: const Text('Ao treinar só uma mão'),
              value: s.autoOtherHand,
              onChanged: (v) => s.autoOtherHand = v,
            ),
            SwitchListTile(
              title: const Text('Guia: tocar a música junto'),
              value: s.guideSound,
              onChanged: (v) => s.guideSound = v,
            ),
            _header(context, 'Microfone'),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Calibrar microfone'),
              subtitle: Text(s.calibrated
                  ? 'Calibrado · atraso ${s.latencyMs} ms'
                  : 'Ainda não calibrado'),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const CalibrationScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: const Text('Afinador / teste do microfone'),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const TunerScreen())),
            ),
            ListTile(
              title: Text('Sensibilidade: ${(s.sensitivity * 100).round()}%'),
              subtitle: Slider(
                value: s.sensitivity,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                onChanged: (v) => s.sensitivity = v,
              ),
            ),
            ListTile(
              title: Text('Atraso do microfone: ${s.latencyMs} ms'),
              subtitle: Slider(
                value: s.latencyMs.toDouble().clamp(0, 400),
                min: 0,
                max: 400,
                divisions: 40,
                onChanged: (v) => s.latencyMs = v.round(),
              ),
            ),
            _header(context, 'Jogo'),
            ListTile(
              title: Text('Janela "Perfeito": ±${s.perfectMs} ms'),
              subtitle: Slider(
                value: s.perfectMs.toDouble(),
                min: 40,
                max: 200,
                divisions: 16,
                onChanged: (v) {
                  s.perfectMs = v.round();
                  if (s.goodMs < s.perfectMs + 20) s.goodMs = s.perfectMs + 20;
                },
              ),
            ),
            ListTile(
              title: Text('Janela "Bom": ±${s.goodMs} ms'),
              subtitle: Slider(
                value: s.goodMs.toDouble().clamp(60, 400),
                min: 60,
                max: 400,
                divisions: 34,
                onChanged: (v) => s.goodMs = v.round().clamp(s.perfectMs + 20, 400),
              ),
            ),
            SwitchListTile(
              title: const Text('Piscar no tempo (metrônomo visual)'),
              value: s.beatFlash,
              onChanged: (v) => s.beatFlash = v,
            ),
            SwitchListTile(
              title: const Text('Vibrar a cada compasso'),
              value: s.vibrateOnBar,
              onChanged: (v) => s.vibrateOnBar = v,
            ),
            SwitchListTile(
              title: const Text('Liberar todas as dificuldades'),
              subtitle: const Text('Sem precisar de 3 estrelas no nível anterior'),
              value: s.unlockAll,
              onChanged: (v) => s.unlockAll = v,
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
      );
}

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/note.dart';
import '../detection/pitch_listener.dart';
import '../services/app_services.dart';

/// Mostra em tempo real a nota que o microfone está ouvindo.
class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key});

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> {
  PitchListener? _listener;
  StreamSubscription<ListenerFrame>? _frameSub;
  StreamSubscription<HeardNote>? _noteSub;
  ListenerFrame? _frame;
  final _recent = <int>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final s = AppServices.of(context).settings;
    final l = PitchListener(
      lowest: s.keyboard.lowest,
      highest: s.keyboard.highest,
      noiseFloor: s.noiseFloor,
      sensitivity: s.sensitivity,
    );
    if (!await l.start()) {
      if (mounted) setState(() => _error = 'Sem permissão de microfone.');
      return;
    }
    if (!mounted) {
      await l.dispose();
      return;
    }
    _listener = l;
    _frameSub = l.frames.listen((f) => setState(() => _frame = f));
    _noteSub = l.notes.listen((n) => setState(() {
          _recent.insert(0, n.midi);
          if (_recent.length > 12) _recent.removeLast();
        }));
  }

  @override
  void dispose() {
    _frameSub?.cancel();
    _noteSub?.cancel();
    _listener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppServices.of(context).settings;
    final naming = s.naming == NoteNaming.none ? NoteNaming.solfege : s.naming;
    final f = _frame;
    final level = f == null ? 0.0 : (f.strongestLevel / 6).clamp(0.0, 1.0);
    return Scaffold(
      appBar: AppBar(title: const Text('Afinador / teste')),
      body: Center(
        child: _error != null
            ? Text(_error!)
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text('Toque notas soltas no teclado e veja se o app reconhece.'),
                    const SizedBox(height: 24),
                    Text(
                      f?.strongest == null ? '—' : Note.name(f!.strongest!, naming, withOctave: true),
                      style: const TextStyle(fontSize: 72, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 280,
                      child: LinearProgressIndicator(value: level, minHeight: 10),
                    ),
                    const SizedBox(height: 4),
                    Text('Nível ${f?.strongestLevel.toStringAsFixed(1) ?? '-'} '
                        '(limiar ${(2.6 / s.sensitivity).toStringAsFixed(1)})',
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 24),
                    const Text('Ataques detectados:'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final m in _recent)
                          Chip(label: Text(Note.name(m, naming, withOctave: true))),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

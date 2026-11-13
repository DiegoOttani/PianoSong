import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../core/note.dart';
import '../library/song_repository.dart';
import '../services/app_services.dart';
import '../song/midi_importer.dart';
import '../song/midi_parser.dart';

/// Escolhe quais partes (instrumentos) do MIDI viram notas no piano.
/// Retorna true quando salva.
class PartsScreen extends StatefulWidget {
  const PartsScreen({
    super.key,
    required this.bytes,
    required this.suggestedTitle,
    required this.source,
    required this.id,
    this.existing,
  });

  final Uint8List bytes;
  final String suggestedTitle;
  final String source;
  final String id;
  final SongEntry? existing;

  @override
  State<PartsScreen> createState() => _PartsScreenState();
}

class _PartsScreenState extends State<PartsScreen> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? widget.suggestedTitle);
  RawMidi? _midi;
  List<MidiPart> _parts = [];
  Set<(int, int)> _selected = {};
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    try {
      final midi = MidiImporter.parse(widget.bytes);
      _midi = midi;
      _parts = MidiImporter.parts(midi);
      final existing = widget.existing?.parts ?? const {};
      _selected = existing.isNotEmpty ? {...existing} : MidiImporter.defaultSelection(_parts);
      if (_parts.isEmpty) _error = 'Este arquivo não tem notas.';
    } catch (e) {
      _error = 'Arquivo MIDI inválido: $e';
    }
  }

  Future<void> _save() async {
    if (_selected.isEmpty) return;
    setState(() => _saving = true);
    final repo = AppServices.of(context).repository;
    final title = _title.text.trim().isEmpty ? widget.suggestedTitle : _title.text.trim();
    if (widget.existing != null) {
      widget.existing!
        ..title = title
        ..parts = _selected;
      await repo.update(widget.existing!);
    } else {
      await repo.addMidi(
        id: widget.id,
        title: title,
        source: widget.source,
        bytes: widget.bytes,
        parts: _selected,
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final selectedNotes =
        _parts.where((p) => _selected.contains(p.id)).fold<int>(0, (s, p) => s + p.noteCount);
    return Scaffold(
      appBar: AppBar(title: const Text('Escolher partes')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                TextField(
                  controller: _title,
                  decoration:
                      const InputDecoration(labelText: 'Nome da música', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Marque as partes que você quer tocar no piano. Pianos já vêm marcados; '
                  'em arquivos de banda, escolha a melodia (e o baixo, se quiser a mão esquerda).',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                for (final p in _parts)
                  CheckboxListTile(
                    value: _selected.contains(p.id),
                    onChanged: p.isDrums
                        ? null
                        : (v) => setState(() {
                              if (v == true) {
                                _selected.add(p.id);
                              } else {
                                _selected.remove(p.id);
                              }
                            }),
                    title: Text(p.label),
                    subtitle: Text(p.isDrums
                        ? 'Bateria (não dá para tocar no piano)'
                        : '${p.noteCount} notas · região de ${Note.name(p.avgPitch.round(), NoteNaming.solfege, withOctave: true)}'),
                  ),
                if (_midi != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('$selectedNotes notas selecionadas',
                        style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
      bottomNavigationBar: _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: _selected.isEmpty || _saving ? null : _save,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: Text(_saving ? 'Salvando…' : 'Salvar na biblioteca'),
                ),
              ),
            ),
    );
  }
}

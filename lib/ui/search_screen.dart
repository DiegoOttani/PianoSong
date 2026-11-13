import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../library/bitmidi_api.dart';
import '../library/web_sources.dart';
import '../services/app_services.dart';
import 'parts_screen.dart';
import 'song_detail_screen.dart';
import 'web_source_screen.dart';
import 'widgets.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  List<BitMidiResult> _results = [];
  int _page = 0;
  int _pageTotal = 0;
  int _total = 0;
  bool _loading = false;
  int? _downloading;

  Future<void> _search({int page = 0}) async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final res = await AppServices.of(context).bitMidi.search(q, page: page);
      if (!mounted) return;
      setState(() {
        _results = page == 0 ? res.results : [..._results, ...res.results];
        _page = page;
        _pageTotal = res.pageTotal;
        _total = res.total;
      });
    } catch (e) {
      if (mounted) showError(context, 'Erro na busca: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(BitMidiResult r) async {
    setState(() => _downloading = r.id);
    try {
      final bytes = await AppServices.of(context).bitMidi.download(r);
      if (!mounted) return;
      await _openParts(PartsScreen(
        bytes: bytes,
        suggestedTitle: r.title,
        source: 'bitmidi',
        id: 'bitmidi-${r.id}',
      ));
    } catch (e) {
      if (mounted) showError(context, 'Erro ao baixar: $e');
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  Future<void> _importFile() async {
    final file = await FilePicker.pickFile(dialogTitle: 'Escolha um arquivo .mid');
    if (file == null || !mounted) return;
    if (!RegExp(r'\.(mid|midi|kar)$', caseSensitive: false).hasMatch(file.name)) {
      showError(context, 'Escolha um arquivo MIDI (.mid)');
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await _openParts(PartsScreen(
      bytes: bytes,
      suggestedTitle: file.name.replaceAll(RegExp(r'\.(mid|midi|kar)$', caseSensitive: false), ''),
      source: 'arquivo',
      id: 'file-${DateTime.now().millisecondsSinceEpoch}',
    ));
  }

  void _openWeb(WebSource source) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WebSourceScreen(source: source, query: _query.text),
    ));
  }

  Future<void> _openParts(PartsScreen screen) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (saved != true || !mounted) return;
    final entry = AppServices.of(context).repository.entries.first;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => SongDetailScreen(entry: entry)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscar músicas'),
        actions: [
          TextButton.icon(
            onPressed: _importFile,
            icon: const Icon(Icons.file_open),
            label: const Text('Importar .mid'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Nome da música (ex.: fur elise, river flows in you)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _search),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('Procurar em:  ', style: TextStyle(fontSize: 12)),
                for (final s in WebSource.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.public, size: 16),
                      label: Text(s.label),
                      onPressed: () => _openWeb(s),
                    ),
                  ),
              ],
            ),
          ),
          if (_loading && _results.isEmpty) const LinearProgressIndicator(),
          if (!_loading && _results.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'A busca abaixo usa o BitMidi, um acervo público de MIDIs. '
                'Para anime e jogos, use os sites acima (MIDIShow e MuseScore têm muitos arranjos de piano): '
                'eles abrem aqui dentro, e ao baixar um MIDI ele já entra no app.',
                textAlign: TextAlign.center,
              ),
            ),
          if (_results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('$_total resultados', style: const TextStyle(fontSize: 12)),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length + (_page + 1 < _pageTotal ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == _results.length) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: OutlinedButton(
                      onPressed: _loading ? null : () => _search(page: _page + 1),
                      child: const Text('Mais resultados'),
                    ),
                  );
                }
                final r = _results[i];
                return ListTile(
                  leading: const Icon(Icons.music_note),
                  title: Text(r.title),
                  subtitle: Text('${r.plays} execuções'),
                  trailing: _downloading == r.id
                      ? const SizedBox(
                          width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download),
                  onTap: _downloading == null ? () => _pick(r) : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:material_ui/material_ui.dart';

import '../game/game_engine.dart';
import '../library/song_repository.dart';
import '../services/app_services.dart';
import '../services/settings.dart';
import '../song/difficulty_generator.dart';
import '../song/range_fitter.dart';
import '../song/song_model.dart';
import 'game_screen.dart';
import 'parts_screen.dart';
import 'widgets.dart';

enum HandChoice {
  both('Duas mãos', {Hand.right, Hand.left}),
  right('Direita', {Hand.right}),
  left('Esquerda', {Hand.left});

  const HandChoice(this.label, this.hands);
  final String label;
  final Set<Hand> hands;
}

class SongDetailScreen extends StatefulWidget {
  const SongDetailScreen({super.key, required this.entry});
  final SongEntry entry;

  @override
  State<SongDetailScreen> createState() => _SongDetailScreenState();
}

class _SongDetailScreenState extends State<SongDetailScreen> {
  FitResult? _fit;
  Object? _error;
  Difficulty _difficulty = Difficulty.beginner;
  HandChoice _hands = HandChoice.both;
  bool _waitMode = true;
  double _speed = Difficulty.beginner.defaultSpeed;
  bool _loop = false;
  RangeValues _loopBars = const RangeValues(0, 4);
  bool _speedUp = true;
  late InputMode _input;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _input = AppServices.of(context).settings.inputMode;
      _load();
    });
  }

  Future<void> _load() async {
    final services = AppServices.of(context);
    try {
      final fit = await services.repository.loadSong(widget.entry, services.settings.keyboard);
      if (!mounted) return;
      // Começa no nível mais alto já liberado.
      final repo = services.repository;
      var d = Difficulty.beginner;
      for (final x in Difficulty.values) {
        if (repo.isUnlocked(widget.entry.id, x, unlockAll: services.settings.unlockAll) &&
            repo.resultsFor(widget.entry.id, x).isNotEmpty) {
          d = x;
        }
      }
      setState(() {
        _fit = fit;
        _difficulty = d;
        _speed = d.defaultSpeed;
        final bars = fit.song.barsMs.length;
        _loopBars = RangeValues(0, (bars > 4 ? 4 : bars - 1).clamp(1, 1 << 20).toDouble());
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Song get _song => DifficultyGenerator.generate(_fit!.song, _difficulty);

  int get _barCount {
    final song = _fit!.song;
    final last = song.durationMs;
    return song.barsMs.where((b) => b < last).length;
  }

  void _start() {
    final services = AppServices.of(context);
    final s = services.settings;
    final song = _song;
    final bars = _fit!.song.barsMs;
    final config = GameConfig(
      song: song,
      speed: _speed,
      waitMode: _waitMode,
      hands: _hands.hands,
      windows: s.windows,
      latencyMs: _input == InputMode.microphone ? s.latencyMs : 0,
      loopStartMs: _loop && bars.isNotEmpty ? bars[_loopBars.start.round()] : null,
      loopEndMs: _loop && bars.isNotEmpty
          ? (_loopBars.end.round() < bars.length
              ? bars[_loopBars.end.round()]
              : song.durationMs)
          : null,
      speedUpOnCleanLoop: _loop && _speedUp,
      leadInMs: (song.beatLengthAt(0) * 4).clamp(1500, 4000),
    );
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => GameScreen(
            entry: widget.entry,
            config: config,
            difficulty: _difficulty,
            inputMode: _input,
          ),
        ))
        .then((_) => mounted ? setState(() {}) : null);
  }

  Future<void> _editParts() async {
    final repo = AppServices.of(context).repository;
    final bytes = await repo.midiBytes(widget.entry);
    if (bytes == null || !mounted) return;
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PartsScreen(
        bytes: bytes,
        suggestedTitle: widget.entry.title,
        existing: widget.entry,
        source: widget.entry.source,
        id: widget.entry.id,
      ),
    ));
    if (changed == true) {
      setState(() => _fit = null);
      _load();
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover música?'),
        content: const Text('O arquivo e o histórico desta música serão apagados do celular.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AppServices.of(context).repository.remove(widget.entry);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry.title),
        actions: [
          if (!widget.entry.isDemo) ...[
            IconButton(
                tooltip: 'Escolher partes do MIDI',
                onPressed: _editParts,
                icon: const Icon(Icons.queue_music)),
            IconButton(tooltip: 'Remover', onPressed: _delete, icon: const Icon(Icons.delete)),
          ],
        ],
      ),
      body: _error != null
          ? Center(child: Text('Não foi possível abrir a música:\n$_error'))
          : _fit == null
              ? const Center(child: CircularProgressIndicator())
              : _body(),
      bottomNavigationBar: _fit == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Tocar'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ),
            ),
    );
  }

  Widget _body() {
    final services = AppServices.of(context);
    final repo = services.repository;
    final fit = _fit!;
    final song = _song;
    final results = repo.resultsFor(widget.entry.id, _difficulty);
    final right = song.notes.where((n) => n.hand == Hand.right).length;
    final left = song.notes.length - right;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${song.notes.length} notas (direita $right · esquerda $left) · '
          '${(fit.song.durationMs / 1000).round()}s · ${fit.song.initialBpm.round()} BPM',
        ),
        if (fit.octaveShift != 0 || fit.foldedNotes > 0)
          Text(
            'Ajustada ao seu teclado (${services.settings.keyboard.label}): '
            '${fit.octaveShift != 0 ? 'transposta ${fit.octaveShift} oitava(s)' : ''}'
            '${fit.foldedNotes > 0 ? ' · ${fit.foldedNotes} notas trazidas para dentro' : ''}',
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
          ),
        const SizedBox(height: 16),
        Text('Dificuldade', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in Difficulty.values)
              _difficultyChip(d, repo, services.settings.unlockAll),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(_difficulty.description, style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: 16),
        SegmentedButton<HandChoice>(
          segments: [
            for (final h in HandChoice.values) ButtonSegment(value: h, label: Text(h.label)),
          ],
          selected: {_hands},
          onSelectionChanged: (s) => setState(() => _hands = s.first),
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Modo espera'), icon: Icon(Icons.hourglass_empty)),
            ButtonSegment(value: false, label: Text('No tempo'), icon: Icon(Icons.speed)),
          ],
          selected: {_waitMode},
          onSelectionChanged: (s) => setState(() => _waitMode = s.first),
        ),
        const SizedBox(height: 8),
        SegmentedButton<InputMode>(
          segments: [
            for (final m in InputMode.values)
              ButtonSegment(
                value: m,
                label: Text(m.label),
                icon: Icon(m == InputMode.microphone ? Icons.mic : Icons.touch_app),
              ),
          ],
          selected: {_input},
          onSelectionChanged: (s) {
            setState(() => _input = s.first);
            services.settings.inputMode = s.first;
          },
        ),
        const SizedBox(height: 16),
        Text('Velocidade: ${(_speed * 100).round()}%'),
        Slider(
          value: _speed,
          min: 0.25,
          max: 1.2,
          divisions: 19,
          label: '${(_speed * 100).round()}%',
          onChanged: (v) => setState(() => _speed = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Repetir um trecho (loop)'),
          value: _loop,
          onChanged: _barCount < 2 ? null : (v) => setState(() => _loop = v),
        ),
        if (_loop) ...[
          Text('Compassos ${_loopBars.start.round() + 1} a ${_loopBars.end.round()}'),
          RangeSlider(
            values: _loopBars,
            min: 0,
            max: _barCount.toDouble(),
            divisions: _barCount,
            onChanged: (v) {
              if (v.end - v.start >= 1) setState(() => _loopBars = v);
            },
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Acelerar 5% a cada volta sem erros'),
            value: _speedUp,
            onChanged: (v) => setState(() => _speedUp = v ?? false),
          ),
        ],
        const Divider(height: 32),
        Text('Seu histórico (${_difficulty.label})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (results.isEmpty)
          const Text('Nenhuma sessão ainda.')
        else ...[
          Text('Recorde: ${repo.bestScore(widget.entry.id, _difficulty)} pontos · '
              '${results.length} sessões'),
          const SizedBox(height: 8),
          Sparkline([for (final r in results.reversed.take(30).toList().reversed) r.accuracy]),
          const SizedBox(height: 4),
          const Text('Precisão nas últimas sessões', style: TextStyle(fontSize: 11)),
        ],
      ],
    );
  }

  Widget _difficultyChip(Difficulty d, SongRepository repo, bool unlockAll) {
    final unlocked = repo.isUnlocked(widget.entry.id, d, unlockAll: unlockAll);
    return ChoiceChip(
      selected: _difficulty == d,
      onSelected: unlocked
          ? (_) => setState(() {
                _difficulty = d;
                _speed = d.defaultSpeed;
              })
          : (_) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Faça 3 estrelas no nível anterior para liberar '
                  '(ou libere tudo nas configurações).'))),
      avatar: unlocked ? null : const Icon(Icons.lock, size: 16),
      label: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(d.label),
          Stars(repo.bestStars(widget.entry.id, d), size: 12),
        ],
      ),
    );
  }
}

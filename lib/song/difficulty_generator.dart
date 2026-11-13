import 'song_model.dart';

enum Difficulty {
  beginner('Iniciante', 0.5, 'Só a melodia da mão direita, simplificada'),
  easy('Fácil', 0.65, 'Melodia + baixo da mão esquerda no início dos compassos'),
  medium('Médio', 0.8, 'Duas mãos, acordes com até 2 notas por mão'),
  original('Original', 1.0, 'A música completa');

  const Difficulty(this.label, this.defaultSpeed, this.description);
  final String label;
  final double defaultSpeed;
  final String description;
}

abstract final class DifficultyGenerator {
  static Song generate(Song song, Difficulty difficulty) => switch (difficulty) {
        Difficulty.beginner => song.copyWith(notes: _melody(song, minGapMs: 350)),
        Difficulty.easy =>
          song.copyWith(notes: [..._melody(song, minGapMs: 200), ..._bassOnBars(song)]),
        Difficulty.medium => song.copyWith(notes: _reduceChords(song)),
        Difficulty.original => song,
      };

  /// Melodia: nota mais aguda de cada acorde da mão direita, quantizada em
  /// colcheias, descartando notas mais rápidas que meio tempo ou que
  /// [minGapMs] (no andamento original).
  static List<NoteEvent> _melody(Song song, {required int minGapMs}) {
    var source = song.notes.where((n) => n.hand == Hand.right).toList();
    if (source.isEmpty) source = song.notes.toList();
    if (source.isEmpty) return [];

    final tops = groupChords(source)
        .map((c) => c.reduce((a, b) => a.pitch >= b.pitch ? a : b))
        .map((n) => n.copyWith(startMs: _quantize(song, n.startMs), hand: Hand.right))
        .toList()
      ..sort(compareNotes);

    final kept = <NoteEvent>[];
    for (final n in tops) {
      if (kept.isNotEmpty) {
        final gap = n.startMs - kept.last.startMs;
        final minGap = song.beatLengthAt(n.startMs) * 0.5 * 0.95;
        if (gap < (minGap > minGapMs ? minGap : minGapMs)) continue;
      }
      kept.add(n);
    }
    // Ajusta durações para não sobrepor a próxima nota.
    return [
      for (var i = 0; i < kept.length; i++)
        if (i + 1 < kept.length)
          kept[i].copyWith(
            durationMs: (kept[i + 1].startMs - kept[i].startMs - 20)
                .clamp(80, kept[i].durationMs < 150 ? 150 : kept[i].durationMs),
          )
        else
          kept[i],
    ];
  }

  /// Uma nota grave da mão esquerda no começo de cada compasso.
  static List<NoteEvent> _bassOnBars(Song song) {
    final left = song.notes.where((n) => n.hand == Hand.left).toList();
    if (left.isEmpty || song.barsMs.isEmpty) return [];
    final out = <NoteEvent>[];
    final bars = song.barsMs;
    for (var i = 0; i < bars.length; i++) {
      final bar = bars[i];
      final tol = song.beatLengthAt(bar) * 0.25;
      final near = left.where((n) => (n.startMs - bar).abs() <= tol);
      if (near.isEmpty) continue;
      final low = near.reduce((a, b) => a.pitch <= b.pitch ? a : b);
      final nextBar = i + 1 < bars.length ? bars[i + 1] : bar + low.durationMs;
      out.add(low.copyWith(
        startMs: bar,
        durationMs: low.durationMs.clamp(80, (nextBar - bar - 20).clamp(80, 1 << 30)),
      ));
    }
    return out;
  }

  /// Acordes com no máximo 2 notas por mão (direita: as 2 mais agudas;
  /// esquerda: a mais grave e a mais aguda).
  static List<NoteEvent> _reduceChords(Song song) {
    final out = <NoteEvent>[];
    for (final chord in groupChords(song.notes)) {
      final right = chord.where((n) => n.hand == Hand.right).toList()
        ..sort((a, b) => b.pitch.compareTo(a.pitch));
      final left = chord.where((n) => n.hand == Hand.left).toList()
        ..sort((a, b) => a.pitch.compareTo(b.pitch));
      out.addAll(right.take(2));
      if (left.length <= 2) {
        out.addAll(left);
      } else {
        out
          ..add(left.first)
          ..add(left.last);
      }
    }
    return out;
  }

  /// Arredonda para a colcheia (meio tempo) mais próxima.
  static int _quantize(Song song, int ms) {
    final beats = song.beatsMs;
    if (beats.length < 2) {
      final half = song.beatLengthAt(ms) / 2;
      return ((ms / half).round() * half).round();
    }
    var lo = 0, hi = beats.length - 2;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (beats[mid] <= ms) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final a = beats[lo], b = beats[lo + 1];
    final candidates = [a, (a + b) ~/ 2, b];
    if (ms < a) return ms;
    return candidates.reduce((x, y) => (x - ms).abs() <= (y - ms).abs() ? x : y);
  }
}

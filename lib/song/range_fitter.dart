import '../core/keyboard_layout.dart';
import 'song_model.dart';

class FitResult {
  const FitResult(this.song, this.octaveShift, this.foldedNotes);
  final Song song;

  /// Quantas oitavas a música inteira foi transposta.
  final int octaveShift;

  /// Notas que ficaram fora e foram trazidas para dentro por oitava.
  final int foldedNotes;
}

/// Faz a música caber no teclado escolhido.
abstract final class RangeFitter {
  static FitResult fit(Song song, KeyboardSize keyboard) {
    if (song.notes.isEmpty) return FitResult(song, 0, 0);

    // 1) Melhor transposição em oitavas (mais notas dentro; empate = menor |k|).
    var bestShift = 0;
    var bestInside = -1;
    for (final k in [0, -1, 1, -2, 2, -3, 3, -4, 4]) {
      final inside = song.notes.where((n) => keyboard.contains(n.pitch + 12 * k)).length;
      if (inside > bestInside) {
        bestInside = inside;
        bestShift = k;
      }
    }

    // 2) Dobra por oitava o que ainda sobrar e remove duplicatas.
    var folded = 0;
    final seen = <(int, int)>{};
    final out = <NoteEvent>[];
    for (final n in song.notes) {
      var p = n.pitch + 12 * bestShift;
      if (!keyboard.contains(p)) {
        folded++;
        while (p < keyboard.lowest) {
          p += 12;
        }
        while (p > keyboard.highest) {
          p -= 12;
        }
        if (!keyboard.contains(p)) continue; // teclado menor que uma oitava
      }
      if (!seen.add((p, n.startMs))) continue;
      out.add(n.copyWith(pitch: p));
    }
    return FitResult(song.copyWith(notes: out), bestShift, folded);
  }
}

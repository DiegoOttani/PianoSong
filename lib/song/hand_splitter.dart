import 'song_model.dart';

/// Divide notas entre mão direita e esquerda quando o MIDI não informa.
///
/// Regras: notas claramente agudas/graves vão direto para a mão certa; na zona
/// ambígua em volta do Dó central vale a mão cuja última posição está mais
/// perto (histerese, para a mão não "pular" a cada nota). Cada mão alcança no
/// máximo [maxSpan] semitons num acorde.
abstract final class HandSplitter {
  static const rightAbove = 64; // Mi4 ou mais agudo -> direita
  static const leftBelow = 55; // Sol3 ou mais grave -> esquerda
  static const maxSpan = 14;

  static List<NoteEvent> split(List<NoteEvent> notes) {
    var lastRight = 67.0;
    var lastLeft = 48.0;
    final out = <NoteEvent>[];

    for (final chord in groupChords(notes)) {
      chord.sort((a, b) => a.pitch.compareTo(b.pitch));
      final right = <NoteEvent>[];
      final left = <NoteEvent>[];
      for (final n in chord) {
        final p = n.pitch;
        final bool isRight;
        if (p >= rightAbove) {
          isRight = true;
        } else if (p <= leftBelow) {
          isRight = false;
        } else {
          final dr = (p - lastRight).abs();
          final dl = (p - lastLeft).abs();
          isRight = dr == dl ? p >= 60 : dr < dl;
        }
        (isRight ? right : left).add(n);
      }

      // Limita a abertura de cada mão.
      while (right.length > 1 && right.last.pitch - right.first.pitch > maxSpan) {
        left.add(right.removeAt(0));
      }
      left.sort((a, b) => a.pitch.compareTo(b.pitch));
      while (left.length > 1 && left.last.pitch - left.first.pitch > maxSpan) {
        right.insert(0, left.removeLast());
      }

      if (right.isNotEmpty) {
        lastRight = right.map((n) => n.pitch).reduce((a, b) => a + b) / right.length;
      }
      if (left.isNotEmpty) {
        lastLeft = left.map((n) => n.pitch).reduce((a, b) => a + b) / left.length;
      }
      out
        ..addAll(right.map((n) => n.copyWith(hand: Hand.right)))
        ..addAll(left.map((n) => n.copyWith(hand: Hand.left)));
    }
    return out..sort(compareNotes);
  }
}

import 'dart:math' as math;

/// Como mostrar o nome das notas.
enum NoteNaming {
  solfege('Dó Ré Mi'),
  letters('C D E'),
  none('Nenhum');

  const NoteNaming(this.label);
  final String label;
}

/// Utilitários para notas MIDI (0–127, Dó central = 60).
abstract final class Note {
  static const middleC = 60;

  static const _solfege = [
    'Dó', 'Dó♯', 'Ré', 'Ré♯', 'Mi', 'Fá', 'Fá♯', 'Sol', 'Sol♯', 'Lá', 'Lá♯', 'Si',
  ];
  static const _letters = [
    'C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B',
  ];
  static const _blackPitchClasses = {1, 3, 6, 8, 10};

  static bool isBlack(int midi) => _blackPitchClasses.contains(midi % 12);

  static bool isWhite(int midi) => !isBlack(midi);

  /// Oitava científica: Dó central (60) = 4.
  static int octave(int midi) => midi ~/ 12 - 1;

  /// Frequência em Hz (A4 = 440 Hz).
  static double frequency(int midi) =>
      440.0 * math.pow(2, (midi - 69) / 12.0).toDouble();

  /// Nota MIDI mais próxima de uma frequência.
  static int fromFrequency(double hz) =>
      (69 + 12 * (math.log(hz / 440.0) / math.ln2)).round();

  /// Nome da nota. Retorna string vazia quando [naming] é [NoteNaming.none].
  static String name(int midi, NoteNaming naming, {bool withOctave = false}) {
    final base = switch (naming) {
      NoteNaming.solfege => _solfege[midi % 12],
      NoteNaming.letters => _letters[midi % 12],
      NoteNaming.none => '',
    };
    if (base.isEmpty || !withOctave) return base;
    return '$base${octave(midi)}';
  }
}

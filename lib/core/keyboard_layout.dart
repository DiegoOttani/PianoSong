import 'note.dart';

/// Tamanhos de teclado comuns e a faixa MIDI de cada um.
enum KeyboardSize {
  keys25(25, 48, 72),
  keys37(37, 48, 84),
  keys49(49, 36, 84),
  keys61(61, 36, 96),
  keys76(76, 28, 103),
  keys88(88, 21, 108);

  const KeyboardSize(this.keys, this.lowest, this.highest);

  final int keys;

  /// Nota MIDI mais grave (inclusive).
  final int lowest;

  /// Nota MIDI mais aguda (inclusive).
  final int highest;

  String get label => '$keys teclas';

  bool contains(int midi) => midi >= lowest && midi <= highest;

  int get whiteKeyCount {
    var count = 0;
    for (var m = lowest; m <= highest; m++) {
      if (Note.isWhite(m)) count++;
    }
    return count;
  }

  static KeyboardSize fromKeys(int keys) =>
      values.firstWhere((s) => s.keys == keys, orElse: () => keys61);
}

/// Posição horizontal de uma tecla (em pixels lógicos).
class KeyRect {
  const KeyRect(this.midi, this.left, this.width, this.isBlack);

  final int midi;
  final double left;
  final double width;
  final bool isBlack;

  double get center => left + width / 2;
  double get right => left + width;
}

/// Calcula a geometria das teclas de um teclado para uma largura total.
class KeyboardGeometry {
  KeyboardGeometry(this.size, this.totalWidth) {
    whiteKeyWidth = totalWidth / size.whiteKeyCount;
    final blackWidth = whiteKeyWidth * 0.6;
    var whiteIndex = 0;
    for (var m = size.lowest; m <= size.highest; m++) {
      if (Note.isWhite(m)) {
        _rects[m] = KeyRect(m, whiteIndex * whiteKeyWidth, whiteKeyWidth, false);
        whiteIndex++;
      } else {
        // Tecla preta fica centralizada na divisa entre as brancas vizinhas.
        final boundary = whiteIndex * whiteKeyWidth;
        _rects[m] = KeyRect(m, boundary - blackWidth / 2, blackWidth, true);
      }
    }
  }

  final KeyboardSize size;
  final double totalWidth;
  late final double whiteKeyWidth;
  final Map<int, KeyRect> _rects = {};

  KeyRect? rectFor(int midi) => _rects[midi];

  Iterable<KeyRect> get whiteKeys => _rects.values.where((r) => !r.isBlack);
  Iterable<KeyRect> get blackKeys => _rects.values.where((r) => r.isBlack);

  /// Tecla sob uma coordenada x (pretas têm prioridade quando [preferBlack]).
  int? keyAt(double x, {bool preferBlack = false}) {
    if (preferBlack) {
      for (final r in blackKeys) {
        if (x >= r.left && x < r.right) return r.midi;
      }
    }
    for (final r in whiteKeys) {
      if (x >= r.left && x < r.right) return r.midi;
    }
    return null;
  }
}

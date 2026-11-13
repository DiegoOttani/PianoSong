import '../song/song_model.dart';

/// Músicas de domínio público escritas à mão, para o app ter conteúdo offline.
abstract final class DemoSongs {
  static const odeId = 'demo-ode';
  static const twinkleId = 'demo-twinkle';

  static const titles = {
    odeId: 'Ode à Alegria (Beethoven)',
    twinkleId: 'Brilha Brilha Estrelinha',
  };

  static Song? byId(String id) => switch (id) {
        odeId => _ode(),
        twinkleId => _twinkle(),
        _ => null,
      };

  // Notas
  static const c3 = 48, f2 = 41, g2 = 43, f3 = 53, g3 = 55;
  static const c4 = 60, d4 = 62, e4 = 64, f4 = 65, g4 = 67, a4 = 69;

  static Song _ode() {
    // (nota, tempos)
    const melody = [
      (e4, 1.0), (e4, 1.0), (f4, 1.0), (g4, 1.0),
      (g4, 1.0), (f4, 1.0), (e4, 1.0), (d4, 1.0),
      (c4, 1.0), (c4, 1.0), (d4, 1.0), (e4, 1.0),
      (e4, 1.5), (d4, 0.5), (d4, 2.0),
      (e4, 1.0), (e4, 1.0), (f4, 1.0), (g4, 1.0),
      (g4, 1.0), (f4, 1.0), (e4, 1.0), (d4, 1.0),
      (c4, 1.0), (c4, 1.0), (d4, 1.0), (e4, 1.0),
      (d4, 1.5), (c4, 0.5), (c4, 2.0),
    ];
    const bass = [
      (c3, 4.0), (g2, 4.0), (c3, 4.0), (g2, 4.0),
      (c3, 4.0), (g2, 4.0), (c3, 4.0), (g2, 2.0), (c3, 2.0),
    ];
    return _build(titles[odeId]!, 100, melody, bass);
  }

  static Song _twinkle() {
    const a = [(c4, 1.0), (c4, 1.0), (g4, 1.0), (g4, 1.0), (a4, 1.0), (a4, 1.0), (g4, 2.0)];
    const b = [(f4, 1.0), (f4, 1.0), (e4, 1.0), (e4, 1.0), (d4, 1.0), (d4, 1.0), (c4, 2.0)];
    const c = [(g4, 1.0), (g4, 1.0), (f4, 1.0), (f4, 1.0), (e4, 1.0), (e4, 1.0), (d4, 2.0)];
    const melody = [...a, ...b, ...c, ...c, ...a, ...b];
    const bassA = [(c3, 2.0), (c3, 2.0), (f3, 2.0), (c3, 2.0)];
    const bassB = [(f3, 2.0), (c3, 2.0), (g3, 2.0), (c3, 2.0)];
    const bassC = [(c3, 2.0), (f3, 2.0), (c3, 2.0), (g3, 2.0)];
    const bass = [...bassA, ...bassB, ...bassC, ...bassC, ...bassA, ...bassB];
    return _build(titles[twinkleId]!, 90, melody, bass);
  }

  static Song _build(
    String title,
    double bpm,
    List<(int, double)> melody,
    List<(int, double)> bass,
  ) {
    final beatMs = 60000 / bpm;
    List<NoteEvent> line(List<(int, double)> notes, Hand hand) {
      final out = <NoteEvent>[];
      var t = 0.0;
      for (final (pitch, beats) in notes) {
        out.add(NoteEvent(
          pitch: pitch,
          startMs: (t * beatMs).round(),
          durationMs: (beats * beatMs * 0.9).round(),
          hand: hand,
        ));
        t += beats;
      }
      return out;
    }

    final totalBeats = melody.fold<double>(0, (s, n) => s + n.$2).ceil();
    return Song(
      title: title,
      initialBpm: bpm,
      notes: [...line(melody, Hand.right), ...line(bass, Hand.left)],
      beatsMs: [for (var i = 0; i <= totalBeats + 4; i++) (i * beatMs).round()],
      barsMs: [for (var i = 0; i <= totalBeats + 4; i += 4) (i * beatMs).round()],
    );
  }
}

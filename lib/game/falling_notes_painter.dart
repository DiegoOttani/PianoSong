import 'package:material_ui/material_ui.dart';

import '../core/keyboard_layout.dart';
import '../core/note.dart';
import '../song/song_model.dart';
import 'game_engine.dart';
import 'scoring.dart';

abstract final class GameColors {
  static const background = Color(0xFF0E1220);
  static const lane = Color(0xFF151A2C);
  static const barLine = Color(0x33FFFFFF);
  static const right = Color(0xFF4FC3F7);
  static const left = Color(0xFF81C784);
  static const inactive = Color(0xFF4A4F63);
  static const perfect = Color(0xFFFFD54F);
  static const good = Color(0xFF64FFDA);
  static const miss = Color(0xFFE57373);
  static const wrong = Color(0xFFFF5252);

  static Color hand(Hand h) => h == Hand.right ? right : left;

  static Color judgement(Judgement j) => switch (j) {
        Judgement.perfect => perfect,
        Judgement.good => good,
        Judgement.miss => miss,
      };
}

/// Brilho temporário numa tecla (acerto, erro ou toque).
class KeyFlash {
  KeyFlash(this.color, this.atMs, {this.label});
  final Color color;
  final double atMs; // relógio real
  final String? label;
}

class FallingNotesPainter extends CustomPainter {
  FallingNotesPainter({
    required this.engine,
    required this.keyboard,
    required this.naming,
    required this.flashes,
    required this.nowMs,
    required this.beatFlash,
    required Listenable repaint,
    this.visibleWindowMs = 2500,
  }) : super(repaint: repaint);

  final GameEngine engine;
  final KeyboardSize keyboard;
  final NoteNaming naming;
  final Map<int, KeyFlash> flashes;
  final double Function() nowMs;
  final bool beatFlash;

  /// Quanto tempo (real, em ms) uma nota leva para cair do topo até o teclado.
  final double visibleWindowMs;

  static const keyboardFraction = 0.24;

  @override
  void paint(Canvas canvas, Size size) {
    final geo = KeyboardGeometry(keyboard, size.width);
    final kbHeight = size.height * keyboardFraction;
    final hitY = size.height - kbHeight;
    final now = nowMs();
    final t = engine.songTimeMs;
    final windowSong = visibleWindowMs * engine.speed;
    double yFor(double songMs) => hitY - (songMs - t) / windowSong * hitY;

    canvas.drawRect(Offset.zero & size, Paint()..color = GameColors.background);

    // Faixas das teclas pretas (ajuda a mirar).
    final lanePaint = Paint()..color = GameColors.lane;
    for (final k in geo.blackKeys) {
      canvas.drawRect(Rect.fromLTWH(k.left, 0, k.width, hitY), lanePaint);
    }
    // Linha em cada Dó.
    final cLine = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    for (final k in geo.whiteKeys.where((k) => k.midi % 12 == 0)) {
      canvas.drawLine(Offset(k.left, 0), Offset(k.left, hitY), cLine);
    }

    // Linhas de compasso.
    final barPaint = Paint()
      ..color = GameColors.barLine
      ..strokeWidth = 1;
    for (final b in engine.config.song.barsMs) {
      final y = yFor(b.toDouble());
      if (y < 0) break;
      if (y <= hitY) canvas.drawLine(Offset(0, y), Offset(size.width, y), barPaint);
    }

    // Região do loop.
    if (engine.config.hasLoop) {
      final y0 = yFor(engine.config.loopEndMs!.toDouble());
      if (y0 > 0 && y0 < hitY) {
        canvas.drawLine(Offset(0, y0), Offset(size.width, y0),
            Paint()
              ..color = Colors.orangeAccent
              ..strokeWidth = 2);
      }
    }

    // Notas caindo.
    final notePaint = Paint();
    final upcoming = <int, Color>{};
    for (final p in engine.notes) {
      final n = p.note;
      final top = yFor(n.endMs.toDouble());
      final bottom = yFor(n.startMs.toDouble());
      if (bottom < 0) break;
      if (top > hitY) continue;
      final rect = geo.rectFor(n.pitch);
      if (rect == null) continue;

      Color color;
      if (!p.active) {
        color = GameColors.inactive;
      } else if (p.judgement == Judgement.miss) {
        color = GameColors.miss.withValues(alpha: 0.55);
      } else if (p.judgement != null) {
        color = GameColors.judgement(p.judgement!).withValues(alpha: 0.35);
      } else {
        color = GameColors.hand(n.hand);
        final untilHit = n.startMs - t;
        if (untilHit < 400 * engine.speed && untilHit > -200) upcoming[n.pitch] = color;
      }
      final r = RRect.fromRectAndRadius(
        Rect.fromLTRB(rect.left + 1, top.clamp(-10.0, hitY), rect.right - 1,
            bottom.clamp(-10.0, hitY)),
        const Radius.circular(4),
      );
      notePaint.color = color;
      canvas.drawRRect(r, notePaint);

      if (naming != NoteNaming.none && p.active && p.judgement == null && r.height > 14) {
        _text(canvas, Note.name(n.pitch, naming), Offset(rect.center, r.bottom - 9),
            fontSize: (rect.width * 0.42).clamp(7.0, 13.0), color: Colors.black87);
      }
    }

    // Linha de acerto.
    canvas.drawRect(Rect.fromLTWH(0, hitY - 2, size.width, 3),
        Paint()..color = engine.waiting ? Colors.orangeAccent : Colors.white70);

    // Flash do tempo (metrônomo visual).
    if (beatFlash) _beatFlash(canvas, size, t);

    _keyboard(canvas, geo, hitY, kbHeight, upcoming, now);
  }

  void _beatFlash(Canvas canvas, Size size, double t) {
    final beats = engine.config.song.beatsMs;
    if (beats.isEmpty) return;
    var lo = 0, hi = beats.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (beats[mid] <= t) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final since = t - beats[lo];
    if (since < 0 || since > 120 * engine.speed) return;
    final isBar = engine.config.song.barsMs.contains(beats[lo]);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, isBar ? 6 : 3),
      Paint()..color = (isBar ? Colors.orangeAccent : Colors.white54),
    );
  }

  void _keyboard(Canvas canvas, KeyboardGeometry geo, double top, double height,
      Map<int, Color> upcoming, double now) {
    final blackHeight = height * 0.62;
    final whitePaint = Paint();
    final border = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    Color? flashColor(int midi) {
      final f = flashes[midi];
      if (f == null) return null;
      final age = now - f.atMs;
      if (age > 350) return null;
      return f.color.withValues(alpha: 1 - age / 350 * 0.6);
    }

    for (final k in geo.whiteKeys) {
      final rect = Rect.fromLTWH(k.left, top, k.width, height);
      whitePaint.color = flashColor(k.midi) ??
          (upcoming[k.midi] != null
              ? Color.lerp(Colors.white, upcoming[k.midi], 0.45)!
              : Colors.white);
      canvas.drawRect(rect, whitePaint);
      canvas.drawRect(rect, border);
      final isC = k.midi % 12 == 0;
      if (naming != NoteNaming.none && (isC || k.width > 18)) {
        _text(
          canvas,
          Note.name(k.midi, naming, withOctave: isC),
          Offset(k.center, top + height - 10),
          fontSize: (k.width * 0.38).clamp(6.0, 12.0),
          color: isC ? Colors.black : Colors.black54,
          bold: isC,
        );
      }
    }
    for (final k in geo.blackKeys) {
      final rect = Rect.fromLTWH(k.left, top, k.width, blackHeight);
      whitePaint.color = flashColor(k.midi) ??
          (upcoming[k.midi] != null
              ? Color.lerp(Colors.black, upcoming[k.midi], 0.6)!
              : const Color(0xFF1B1B1B));
      canvas.drawRRect(
          RRect.fromRectAndCorners(rect,
              bottomLeft: const Radius.circular(2), bottomRight: const Radius.circular(2)),
          whitePaint);
    }

    // Rótulos de acerto ("Perfeito!") acima das teclas.
    flashes.forEach((midi, f) {
      if (f.label == null) return;
      final age = now - f.atMs;
      if (age > 600) return;
      final k = geo.rectFor(midi);
      if (k == null) return;
      _text(canvas, f.label!, Offset(k.center, top - 14 - age / 25),
          fontSize: 12, color: f.color.withValues(alpha: 1 - age / 600), bold: true);
    });
  }

  void _text(Canvas canvas, String s, Offset center,
      {double fontSize = 12, Color color = Colors.white, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant FallingNotesPainter old) => true;
}

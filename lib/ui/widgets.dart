import 'package:material_ui/material_ui.dart';

class Stars extends StatelessWidget {
  const Stars(this.count, {super.key, this.size = 18});
  final int count;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Icon(i < count ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size, color: i < count ? Colors.amber : Colors.white24),
        ],
      );
}

/// Mini gráfico de linha (evolução da precisão).
class Sparkline extends StatelessWidget {
  const Sparkline(this.values, {super.key, this.height = 48});
  final List<double> values;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
            painter: _SparkPainter(values, Theme.of(context).colorScheme.primary)),
      );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - values[i].clamp(0.0, 1.0) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.values != values;
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
}

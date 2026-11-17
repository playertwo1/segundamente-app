import 'package:flutter/material.dart';
import 'package:memex/ui/core/themes/app_colors.dart';

/// The round "complete" mark of a task card. The visual circle is 22 dp; the
/// touch target around it is 48 dp and is added by the caller.
class TodoDoneCircle extends StatelessWidget {
  const TodoDoneCircle({
    super.key,
    required this.ring,
    required this.fill,
    this.fillProgress = 0,
    this.tickProgress = 0,
    this.scale = 1,
  });

  final Color ring;
  final Color fill;

  /// 0 empty, 1 filled with [fill].
  final double fillProgress;

  /// 0 no tick, 1 full tick drawn in black.
  final double tickProgress;

  final double scale;

  @override
  Widget build(BuildContext context) => Transform.scale(
        scale: scale,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.lerp(Colors.transparent, fill, fillProgress),
            border: Border.all(color: ring, width: 1.5),
          ),
          child: tickProgress <= 0
              ? null
              : CustomPaint(
                  painter: _TickPainter(tickProgress),
                ),
        ),
      );
}

class _TickPainter extends CustomPainter {
  const _TickPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 22;
    final path = Path()
      ..moveTo(6.2 * s, 11.6 * s)
      ..lineTo(9.6 * s, 15 * s)
      ..lineTo(15.8 * s, 7.9 * s);
    final paint = Paint()
      ..color = AppColors.onPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TickPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

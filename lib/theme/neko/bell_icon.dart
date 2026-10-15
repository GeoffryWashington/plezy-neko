import 'package:flutter/material.dart';

import 'neko_decor.dart';

/// A small golden bell icon drawn with [CustomPaint].
///
/// On non-Neko themes renders [SizedBox.shrink].
class BellIcon extends StatelessWidget {
  final double size;

  const BellIcon({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    final decor = nekoDecor(context);
    if (decor == null) return const SizedBox.shrink();

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BellPainter(cocoa: decor.cocoa),
      ),
    );
  }
}

class _BellPainter extends CustomPainter {
  final Color cocoa;

  _BellPainter({required this.cocoa});

  static const _gold = Color(0xFFF2C14E);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    final bodyPaint = Paint()
      ..color = _gold
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = cocoa
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Bell body – a dome shape.
    final bodyPath = Path()
      ..moveTo(cx - w * 0.35, h * 0.75)
      ..lineTo(cx - w * 0.35, h * 0.45)
      ..quadraticBezierTo(cx - w * 0.35, h * 0.1, cx, h * 0.08)
      ..quadraticBezierTo(cx + w * 0.35, h * 0.1, cx + w * 0.35, h * 0.45)
      ..lineTo(cx + w * 0.35, h * 0.75)
      ..lineTo(cx - w * 0.35, h * 0.75)
      ..close();

    canvas.drawPath(bodyPath, bodyPaint);
    canvas.drawPath(bodyPath, strokePaint);

    // Slot line across the lower third.
    final slotY = h * 0.65;
    canvas.drawLine(
      Offset(cx - w * 0.3, slotY),
      Offset(cx + w * 0.3, slotY),
      strokePaint,
    );

    // Clapper ball.
    canvas.drawCircle(Offset(cx, h * 0.82), w * 0.08, bodyPaint);
    canvas.drawCircle(Offset(cx, h * 0.82), w * 0.08, strokePaint);

    // Tiny highlight.
    final highlightPaint = Paint()
      ..color = Colors.white.withAlpha(100)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx - w * 0.12, h * 0.3), w * 0.06, highlightPaint);
  }

  @override
  bool shouldRepaint(covariant _BellPainter oldDelegate) =>
      oldDelegate.cocoa != cocoa;
}

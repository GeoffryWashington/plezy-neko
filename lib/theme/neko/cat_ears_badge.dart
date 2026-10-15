import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'neko_decor.dart';

/// Wraps [child] with two small rounded-triangle cat ears poking out above
/// the top edge, at roughly 22 % and 78 % of the child's width.
///
/// On non-Neko themes the [child] is returned unchanged.
class CatEarsBadge extends StatelessWidget {
  final Widget child;
  final double earSize;

  const CatEarsBadge({
    super.key,
    required this.child,
    this.earSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    final decor = nekoDecor(context);
    if (decor == null) return child;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -earSize,
          left: 0,
          right: 0,
          height: earSize,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _CatEarsPainter(
                earSize: earSize,
                accent: decor.accent,
                accentSoft: decor.accentSoft,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CatEarsPainter extends CustomPainter {
  final double earSize;
  final Color accent;
  final Color accentSoft;

  _CatEarsPainter({
    required this.earSize,
    required this.accent,
    required this.accentSoft,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = earSize;
    const tilt = 18.0 * math.pi / 180.0;

    // Left ear at ~22 % of width, tilted outward (counter-clockwise).
    _drawEar(canvas, Offset(w * 0.22, h), h, -tilt);
    // Right ear at ~78 % of width, tilted outward (clockwise).
    _drawEar(canvas, Offset(w * 0.78, h), h, tilt);
  }

  void _drawEar(Canvas canvas, Offset base, double size, double tilt) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(tilt);

    // Outer ear – rounded triangle.
    final outerPath = Path()
      ..moveTo(-size * 0.4, 0)
      ..quadraticBezierTo(-size * 0.35, -size * 0.7, 0, -size)
      ..quadraticBezierTo(size * 0.35, -size * 0.7, size * 0.4, 0)
      ..close();
    canvas.drawPath(outerPath, Paint()..color = accent);

    // Inner ear – smaller rounded triangle.
    const s = 0.55;
    final innerPath = Path()
      ..moveTo(-size * 0.4 * s, 0)
      ..quadraticBezierTo(-size * 0.35 * s, -size * 0.7 * s, 0, -size * s)
      ..quadraticBezierTo(size * 0.35 * s, -size * 0.7 * s, size * 0.4 * s, 0)
      ..close();
    canvas.drawPath(innerPath, Paint()..color = accentSoft);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CatEarsPainter oldDelegate) =>
      oldDelegate.earSize != earSize ||
      oldDelegate.accent != accent ||
      oldDelegate.accentSoft != accentSoft;
}

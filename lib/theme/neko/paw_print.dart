import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'neko_decor.dart';

/// Paints a single paw print centred at [center] with the given [size].
///
/// The print consists of one large rounded palm pad and four smaller toe
/// beans arced above it. [rotation] is in radians.
void paintPawPrint(
  Canvas canvas,
  Offset center,
  double size,
  Paint paint, {
  double rotation = 0,
}) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(rotation);

  // Palm pad – a rounded ellipse, ~0.55 * size wide.
  final palmW = size * 0.55;
  final palmH = size * 0.42;
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(0, size * 0.08),
      width: palmW,
      height: palmH,
    ),
    paint,
  );

  // Four toe beans arced above the palm.
  const toeAngles = [-145.0, -115.0, -65.0, -35.0];
  final toeR = size * 0.11;
  final arcR = size * 0.30;
  for (final deg in toeAngles) {
    final rad = deg * math.pi / 180.0;
    final cx = arcR * math.cos(rad);
    final cy = size * 0.08 - arcR * math.sin(rad);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy),
        width: toeR * 2,
        height: toeR * 1.5,
      ),
      paint,
    );
  }

  canvas.restore();
}

/// A full-screen backdrop of deterministic, scattered paw prints painted
/// behind [child] in the Neko accent colour at low [opacity].
///
/// On non-Neko themes the [child] is returned unchanged.
class PawPrintBackdrop extends StatelessWidget {
  final Widget child;
  final double opacity;

  const PawPrintBackdrop({
    super.key,
    required this.child,
    this.opacity = 0.06,
  });

  @override
  Widget build(BuildContext context) {
    final decor = nekoDecor(context);
    if (decor == null) return child;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _PawPrintPainter(
                  color: decor.accent,
                  opacity: opacity,
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _PawPrintPainter extends CustomPainter {
  final Color color;
  final double opacity;

  _PawPrintPainter({required this.color, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withAlpha((opacity * 255).round())
      ..style = PaintingStyle.fill;

    const cell = 120.0;
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();

    for (var c = 0; c < cols; c++) {
      for (var r = 0; r < rows; r++) {
        final h = _hash(c, r);
        final dx = ((h % 100) / 100.0 - 0.5) * 50;
        final dy = (((h >> 8) % 100) / 100.0 - 0.5) * 50;
        final rot = ((h >> 16) % 360) / 360.0 * 2 * math.pi;
        final pawSize = 36.0 + (h >> 24) % 21; // 36..56

        final center = Offset(
          c * cell + cell / 2 + dx,
          r * cell + cell / 2 + dy,
        );
        paintPawPrint(canvas, center, pawSize, paint, rotation: rot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PawPrintPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.opacity != opacity;

  /// Deterministic integer hash – stable across repaints, no time-based seed.
  static int _hash(int col, int row) {
    var h = col * 73856093 ^ row * 19349663;
    h = (h ^ (h >> 13)) * 0x5bd1e995;
    h = h ^ (h >> 15);
    return h & 0x7FFFFFFF;
  }
}

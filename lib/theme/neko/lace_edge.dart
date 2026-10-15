import 'package:flutter/material.dart';

import 'neko_decor.dart';

/// A decorative scalloped lace strip.
///
/// Renders a row of semicircle scallops filled with [NekoDecor.cream],
/// a 1 px hairline in cocoa @ 25 %, and a small eyelet hole in the centre
/// of each scallop. Set [flip] to `true` to mirror vertically (scallops
/// pointing up instead of down).
///
/// On non-Neko themes renders [SizedBox.shrink].
class LaceEdge extends StatelessWidget {
  final double height;
  final bool flip;

  const LaceEdge({
    super.key,
    this.height = 12,
    this.flip = false,
  });

  @override
  Widget build(BuildContext context) {
    final decor = nekoDecor(context);
    if (decor == null) return const SizedBox.shrink();

    final scallopRadius = height * 0.8;
    final totalHeight = height + scallopRadius;

    return SizedBox(
      width: double.infinity,
      height: totalHeight,
      child: CustomPaint(
        painter: _LaceEdgePainter(
          bandHeight: height,
          scallopRadius: scallopRadius,
          flip: flip,
          cream: decor.cream,
          accent: decor.accent,
        ),
      ),
    );
  }
}

class _LaceEdgePainter extends CustomPainter {
  final double bandHeight;
  final double scallopRadius;
  final bool flip;
  final Color cream;
  final Color accent;

  _LaceEdgePainter({
    required this.bandHeight,
    required this.scallopRadius,
    required this.flip,
    required this.cream,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()..color = cream;
    final hairlinePaint = Paint()
      ..color = accent.withAlpha((0.35 * 255).round())
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final scallopStrokePaint = Paint()
      ..color = accent.withAlpha((0.45 * 255).round())
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final eyeletPaint = Paint()
      ..color = accent.withAlpha((0.55 * 255).round());

    // Straight cream band.
    final bandRect = flip
        ? Rect.fromLTWH(0, scallopRadius, size.width, bandHeight)
        : Rect.fromLTWH(0, 0, size.width, bandHeight);
    canvas.drawRect(bandRect, fillPaint);

    // Hairline along the straight edge.
    final hairlineY = flip ? scallopRadius : bandHeight;
    canvas.drawLine(
      Offset(0, hairlineY),
      Offset(size.width, hairlineY),
      hairlinePaint,
    );

    // Scallops + eyelets.
    final scallopDiameter = scallopRadius * 2;
    final numScallops = (size.width / scallopRadius).ceil();
    final eyeletRadius = bandHeight * 0.12;

    for (var i = 0; i < numScallops; i++) {
      final cx = i * scallopRadius + scallopRadius / 2;

      // Semicircle centre sits on the straight edge.
      final semicircleCenter = flip
          ? Offset(cx, scallopRadius)
          : Offset(cx, bandHeight);

      final rect = Rect.fromCenter(
        center: semicircleCenter,
        width: scallopDiameter,
        height: scallopDiameter,
      );

      // Clip to show only the half that hangs off the band.
      canvas.save();
      if (flip) {
        canvas.clipRect(Rect.fromLTWH(0, 0, size.width, scallopRadius));
      } else {
        canvas.clipRect(
          Rect.fromLTWH(0, bandHeight, size.width, scallopRadius),
        );
      }
      canvas.drawOval(rect, fillPaint);
      canvas.drawOval(rect, scallopStrokePaint);
      canvas.restore();

      // Eyelet in the centre of each scallop.
      final eyeletCenter = flip
          ? Offset(cx, scallopRadius * 0.5)
          : Offset(cx, bandHeight + scallopRadius * 0.5);
      canvas.drawCircle(eyeletCenter, eyeletRadius, eyeletPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LaceEdgePainter oldDelegate) =>
      oldDelegate.bandHeight != bandHeight ||
      oldDelegate.scallopRadius != scallopRadius ||
      oldDelegate.flip != flip ||
      oldDelegate.cream != cream ||
      oldDelegate.accent != accent;
}

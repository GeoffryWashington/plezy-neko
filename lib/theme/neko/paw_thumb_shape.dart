import 'package:flutter/material.dart';

import 'paw_print.dart';

/// A slider thumb that renders a soft white circle with a paw print on top.
///
/// Used by the Neko Maid theme to replace the default timeline handle so the
/// scrubber feels on-brand without distracting from the picture.
class PawThumbShape extends SliderComponentShape {
  final Color color;
  final double size;

  const PawThumbShape({required this.color, this.size = 18});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.square(size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final radius = size * 0.55;

    // Soft drop-shadow behind the circle.
    final circlePath = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.drawShadow(circlePath, Colors.black, 2, false);

    // White circle body.
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);

    // Paw print centred on the circle.
    paintPawPrint(canvas, center, size * 0.8, Paint()..color = color);
  }
}

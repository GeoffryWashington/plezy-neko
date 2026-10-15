import 'package:flutter/material.dart';

/// A slider thumb that renders a paw icon glyph.
///
/// Used by the Neko Maid theme to replace the default timeline handle so the
/// scrubber feels on-brand without distracting from the picture.
class PawThumbShape extends SliderComponentShape {
  final Color color;
  final double size;

  const PawThumbShape({required this.color, this.size = 24});

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

    void paintGlyph(double fontSize, Color glyphColor, Offset offset) {
      final painter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(Icons.pets.codePoint),
          style: TextStyle(
            fontFamily: Icons.pets.fontFamily,
            package: Icons.pets.fontPackage,
            fontSize: fontSize,
            color: glyphColor,
          ),
        ),
        textDirection: textDirection,
      )..layout();
      final topLeft =
          center - Offset(painter.width / 2, painter.height / 2) + offset;
      painter.paint(canvas, topLeft);
    }

    // Soft shadow behind the glyph.
    paintGlyph(size, Colors.black.withValues(alpha: 0.35), const Offset(0, 1));

    // White outline pass (full size – acts as the border).
    paintGlyph(size, Colors.white, Offset.zero);

    // Colored fill pass (slightly smaller so the white shows as a ~2 px rim).
    paintGlyph(size - 4, color, Offset.zero);
  }
}

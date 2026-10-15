import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import 'neko_decor.dart';

/// A sleepy cat face illustration above a message, for empty states.
///
/// On non-Neko themes renders only the [message] text (or [SizedBox.shrink]
/// if [message] is null).
class NekoEmpty extends StatelessWidget {
  final String? message;
  final double size;

  const NekoEmpty({
    super.key,
    this.message,
    this.size = 96,
  });

  @override
  Widget build(BuildContext context) {
    final decor = nekoDecor(context);
    final text = message ?? t.neko.empty;

    if (decor == null) {
      if (message == null) return const SizedBox.shrink();
      return Center(child: Text(text));
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _SleepyCatPainter(
                cream: decor.cream,
                cocoa: decor.cocoa,
                accent: decor.accent,
                accentSoft: decor.accentSoft,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: decor.text.withAlpha((0.7 * 255).round()),
                ),
          ),
        ],
      ),
    );
  }
}

class _SleepyCatPainter extends CustomPainter {
  final Color cream;
  final Color cocoa;
  final Color accent;
  final Color accentSoft;

  _SleepyCatPainter({
    required this.cream,
    required this.cocoa,
    required this.accent,
    required this.accentSoft,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cx = w / 2;
    final cy = w / 2;
    final headR = w * 0.32;

    final headFill = Paint()..color = cream;
    final headStroke = Paint()
      ..color = cocoa
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final earOuter = Paint()..color = cream;
    final earInner = Paint()..color = accentSoft;
    final eyePaint = Paint()
      ..color = cocoa
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final nosePaint = Paint()..color = accent;
    final whiskerPaint = Paint()
      ..color = cocoa.withAlpha((0.6 * 255).round())
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final zPaint = Paint()
      ..color = cocoa.withAlpha((0.5 * 255).round())
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    // --- Ears (drawn before head so head overlaps their base) ---

    // Left ear.
    final leftEar = Path()
      ..moveTo(cx - headR * 0.7, cy - headR * 0.5)
      ..lineTo(cx - headR * 0.9, cy - headR * 1.2)
      ..lineTo(cx - headR * 0.2, cy - headR * 0.8)
      ..close();
    canvas.drawPath(leftEar, earOuter);
    canvas.drawPath(leftEar, headStroke);

    final leftEarInner = Path()
      ..moveTo(cx - headR * 0.6, cy - headR * 0.55)
      ..lineTo(cx - headR * 0.75, cy - headR * 1.0)
      ..lineTo(cx - headR * 0.3, cy - headR * 0.75)
      ..close();
    canvas.drawPath(leftEarInner, earInner);

    // Right ear.
    final rightEar = Path()
      ..moveTo(cx + headR * 0.7, cy - headR * 0.5)
      ..lineTo(cx + headR * 0.9, cy - headR * 1.2)
      ..lineTo(cx + headR * 0.2, cy - headR * 0.8)
      ..close();
    canvas.drawPath(rightEar, earOuter);
    canvas.drawPath(rightEar, headStroke);

    final rightEarInner = Path()
      ..moveTo(cx + headR * 0.6, cy - headR * 0.55)
      ..lineTo(cx + headR * 0.75, cy - headR * 1.0)
      ..lineTo(cx + headR * 0.3, cy - headR * 0.75)
      ..close();
    canvas.drawPath(rightEarInner, earInner);

    // --- Head ---
    canvas.drawCircle(Offset(cx, cy), headR, headFill);
    canvas.drawCircle(Offset(cx, cy), headR, headStroke);

    // --- Closed eyes – "^ ^" arcs ---
    final eyeY = cy - headR * 0.1;
    final eyeSpacing = headR * 0.35;
    final eyeW = headR * 0.2;

    final leftEye = Path()
      ..moveTo(cx - eyeSpacing - eyeW, eyeY)
      ..quadraticBezierTo(
        cx - eyeSpacing,
        eyeY - eyeW * 0.8,
        cx - eyeSpacing + eyeW,
        eyeY,
      );
    canvas.drawPath(leftEye, eyePaint);

    final rightEye = Path()
      ..moveTo(cx + eyeSpacing - eyeW, eyeY)
      ..quadraticBezierTo(
        cx + eyeSpacing,
        eyeY - eyeW * 0.8,
        cx + eyeSpacing + eyeW,
        eyeY,
      );
    canvas.drawPath(rightEye, eyePaint);

    // --- Nose ---
    canvas.drawCircle(Offset(cx, cy + headR * 0.15), headR * 0.06, nosePaint);

    // --- Whiskers ---
    final wy = cy + headR * 0.2;
    final wl = headR * 0.4;
    // Left.
    canvas.drawLine(
      Offset(cx - headR * 0.3, wy - headR * 0.05),
      Offset(cx - headR * 0.3 - wl, wy - headR * 0.15),
      whiskerPaint,
    );
    canvas.drawLine(
      Offset(cx - headR * 0.3, wy),
      Offset(cx - headR * 0.3 - wl, wy),
      whiskerPaint,
    );
    canvas.drawLine(
      Offset(cx - headR * 0.3, wy + headR * 0.05),
      Offset(cx - headR * 0.3 - wl, wy + headR * 0.15),
      whiskerPaint,
    );
    // Right.
    canvas.drawLine(
      Offset(cx + headR * 0.3, wy - headR * 0.05),
      Offset(cx + headR * 0.3 + wl, wy - headR * 0.15),
      whiskerPaint,
    );
    canvas.drawLine(
      Offset(cx + headR * 0.3, wy),
      Offset(cx + headR * 0.3 + wl, wy),
      whiskerPaint,
    );
    canvas.drawLine(
      Offset(cx + headR * 0.3, wy + headR * 0.05),
      Offset(cx + headR * 0.3 + wl, wy + headR * 0.15),
      whiskerPaint,
    );

    // --- "z z" floating top-right (text-free strokes) ---
    final zBase = Offset(cx + headR * 0.8, cy - headR * 0.9);
    _drawZ(canvas, zBase, headR * 0.15, zPaint);
    _drawZ(
      canvas,
      Offset(zBase.dx + headR * 0.2, zBase.dy - headR * 0.2),
      headR * 0.1,
      zPaint,
    );
  }

  void _drawZ(Canvas canvas, Offset origin, double s, Paint paint) {
    final path = Path()
      ..moveTo(origin.dx, origin.dy)
      ..lineTo(origin.dx + s, origin.dy)
      ..lineTo(origin.dx, origin.dy + s)
      ..lineTo(origin.dx + s, origin.dy + s);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SleepyCatPainter oldDelegate) =>
      oldDelegate.cream != cream ||
      oldDelegate.cocoa != cocoa ||
      oldDelegate.accent != accent ||
      oldDelegate.accentSoft != accentSoft;
}

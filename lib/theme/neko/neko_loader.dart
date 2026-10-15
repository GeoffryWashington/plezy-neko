import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import 'neko_decor.dart';
import 'paw_print.dart';

/// Three paw prints that hop in sequence, with an optional caption.
///
/// On non-Neko themes renders a standard [CircularProgressIndicator].
class NekoLoader extends StatefulWidget {
  final double size;
  final String? caption;
  final bool showCaption;

  const NekoLoader({
    super.key,
    this.size = 48,
    this.caption,
    this.showCaption = true,
  });

  @override
  State<NekoLoader> createState() => _NekoLoaderState();
}

class _NekoLoaderState extends State<NekoLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final decor = nekoDecor(context);
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) == true;
    final label = widget.caption ?? t.neko.loading;

    if (decor == null) {
      return Semantics(
        label: label,
        liveRegion: false,
        child: SizedBox.square(
          dimension: widget.size,
          child: const CircularProgressIndicator(),
        ),
      );
    }

    if (reducedMotion) {
      return Semantics(
        label: label,
        liveRegion: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return SizedBox(
                  width: widget.size * 0.42,
                  height: widget.size * 0.42,
                  child: CustomPaint(
                    painter: _PawHopPainter(
                      pawSize: widget.size * 0.42,
                      color: decor.accent,
                      hopAmount: 0.0,
                      scale: 0.95,
                      opacity: 1.0,
                    ),
                  ),
                );
              }),
            ),
            if (widget.showCaption) ...[
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: decor.text.withAlpha((0.7 * 255).round()),
                    ),
              ),
            ],
          ],
        ),
      );
    }

    return Semantics(
      label: label,
      liveRegion: false,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final localT =
                      ((_controller.value * 3.0 - i) % 1.0 + 1.0) % 1.0;
                  final hop = math.sin(math.pi * localT);
                  return SizedBox(
                    width: widget.size * 0.42,
                    height: widget.size * 0.42,
                    child: CustomPaint(
                      painter: _PawHopPainter(
                        pawSize: widget.size * 0.42,
                        color: decor.accent,
                        hopAmount: hop,
                        scale: 0.9 + 0.15 * hop,
                        opacity: 0.45 + 0.55 * hop,
                      ),
                    ),
                  );
                }),
              ),
              if (widget.showCaption) ...[
                const SizedBox(height: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: decor.text.withAlpha((0.7 * 255).round()),
                      ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PawHopPainter extends CustomPainter {
  final double pawSize;
  final Color color;
  final double hopAmount;
  final double scale;
  final double opacity;

  _PawHopPainter({
    required this.pawSize,
    required this.color,
    required this.hopAmount,
    required this.scale,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withAlpha((opacity * 255).round())
      ..style = PaintingStyle.fill;

    final hopOffset = -hopAmount * pawSize * 0.18;
    final center = Offset(size.width / 2, size.height / 2 + hopOffset);
    final effectiveSize = pawSize * scale;

    paintPawPrint(canvas, center, effectiveSize, paint);
  }

  @override
  bool shouldRepaint(covariant _PawHopPainter oldDelegate) =>
      oldDelegate.hopAmount != hopAmount ||
      oldDelegate.scale != scale ||
      oldDelegate.opacity != opacity ||
      oldDelegate.color != color ||
      oldDelegate.pawSize != pawSize;
}

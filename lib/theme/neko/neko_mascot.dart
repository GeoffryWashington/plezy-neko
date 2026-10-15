import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'neko_decor.dart';

/// A dancing catgirl mascot that appears on neko-themed screens.
///
/// Renders nothing when the active theme is not a Neko theme.
class NekoMascot extends StatefulWidget {
  final double height;
  final bool dancing;
  final bool showHearts;

  const NekoMascot({
    super.key,
    this.height = 160,
    this.dancing = true,
    this.showHearts = true,
  });

  @override
  State<NekoMascot> createState() => _NekoMascotState();
}

class _NekoMascotState extends State<NekoMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const List<String> _frames = [
    'assets/neko/mascot_frames/frame_0.png',
    'assets/neko/mascot_frames/frame_1.png',
    'assets/neko/mascot_frames/frame_2.png',
    'assets/neko/mascot_frames/frame_3.png',
    'assets/neko/mascot_frames/frame_4.png',
    'assets/neko/mascot_frames/frame_5.png',
    'assets/neko/mascot_frames/frame_6.png',
    'assets/neko/mascot_frames/frame_7.png',
  ];

  static const String _staticFrame = 'assets/neko/mascot.png';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1280),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final path in _frames) {
      precacheImage(AssetImage(path), context);
    }
    precacheImage(AssetImage(_staticFrame), context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _frameIndexForPhase(double phase) {
    final step = (phase * _frames.length).floor() % _frames.length;
    return step;
  }

  @override
  Widget build(BuildContext context) {
    final decor = nekoDecor(context);
    if (decor == null) {
      return const SizedBox.shrink();
    }

    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) == true;
    final dancing = widget.dancing && !reducedMotion;

    final width = widget.height * 0.62;
    final totalHeight = widget.height + widget.height * 0.06;

    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          width: width,
          height: totalHeight,
          child: dancing ? _buildDancing(decor) : _buildStatic(decor),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Static (non-dancing / reduced-motion)
  // ---------------------------------------------------------------------------

  Widget _buildStatic(NekoDecor decor) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        Positioned(
          bottom: 0,
          child: CustomPaint(
            size: Size(widget.height * 0.42, widget.height * 0.06),
            painter: _OvalShadowPainter(
              color: decor.cocoa.withValues(alpha: 0.18),
            ),
          ),
        ),
        Image.asset(
          _staticFrame,
          height: widget.height,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Dancing
  // ---------------------------------------------------------------------------

  Widget _buildDancing(NekoDecor decor) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = _controller.value;
        final frameIndex = _frameIndexForPhase(phase);
        final framePath = _frames[frameIndex];

        // Vertical bounce: 4 small hops per cycle.
        final bounce =
            -math.sin(2 * math.pi * phase * 4).abs() * widget.height * 0.035;

        // Squash & stretch.
        final scaleY = 1 + 0.03 * math.cos(2 * math.pi * phase * 4);
        final scaleX = 2 - scaleY;

        // Sway rotation ±3°.
        final swayAngle = math.sin(2 * math.pi * phase) * (3 * math.pi / 180);

        // Shadow shrinks a bit when she is up.
        final maxBounce = widget.height * 0.035;
        final shadowScale = 1.0 - (bounce.abs() / maxBounce) * 0.15;

        final shadowColor = decor.cocoa.withValues(alpha: 0.18);

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // Soft oval shadow under the feet.
            Positioned(
              bottom: 0,
              child: Transform.scale(
                scale: shadowScale,
                child: CustomPaint(
                  size: Size(widget.height * 0.42, widget.height * 0.06),
                  painter: _OvalShadowPainter(color: shadowColor),
                ),
              ),
            ),
            // Mascot with layered procedural motion.
            Transform.translate(
              offset: Offset(0, bounce),
              child: Transform.rotate(
                angle: swayAngle,
                alignment: Alignment.bottomCenter,
                child: Transform.scale(
                  scaleX: scaleX,
                  scaleY: scaleY,
                  alignment: Alignment.bottomCenter,
                  child: Image.asset(
                    framePath,
                    height: widget.height,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
            // Floating hearts / music notes (max 4 alive; we spawn 3 per cycle).
            if (widget.showHearts) ..._buildHearts(decor, phase),
          ],
        );
      },
    );
  }

  /// Derives heart / note positions purely from [phase] (no timers).
  List<Widget> _buildHearts(NekoDecor decor, double phase) {
    const spawnPhases = [0.1, 0.43, 0.76];
    const lifetime = 0.75; // 960 ms / 1280 ms cycle
    final result = <Widget>[];

    for (var i = 0; i < spawnPhases.length; i++) {
      var age = (phase - spawnPhases[i]) % 1.0;
      if (age < 0) age += 1.0;

      if (age >= lifetime) continue;

      final progress = age / lifetime;
      final opacity = 1.0 - progress;
      final drift = widget.height * 0.35 * progress;
      final isLeft = i.isEven;
      final color = i.isEven ? decor.accent : decor.lavender;
      final isHeart = i.isEven;

      result.add(
        Positioned(
          bottom: widget.height * 0.85 + drift,
          left: isLeft ? widget.height * 0.08 : null,
          right: isLeft ? null : widget.height * 0.08,
          child: Opacity(
            opacity: opacity,
            child: CustomPaint(
              size: const Size(14, 14),
              painter: isHeart
                  ? _HeartPainter(color: color)
                  : _MusicNotePainter(color: color),
            ),
          ),
        ),
      );
    }

    return result;
  }
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

class _OvalShadowPainter extends CustomPainter {
  final Color color;

  const _OvalShadowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawOval(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _OvalShadowPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _HeartPainter extends CustomPainter {
  final Color color;

  const _HeartPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Two arcs + bottom point.
    final path = Path()
      ..moveTo(w / 2, h)
      ..arcTo(Rect.fromLTWH(0, 0, w / 2, h * 0.7), math.pi, math.pi, false)
      ..arcTo(Rect.fromLTWH(w / 2, 0, w / 2, h * 0.7), math.pi, math.pi, true)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeartPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MusicNotePainter extends CustomPainter {
  final Color color;

  const _MusicNotePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Filled oval (note head).
    canvas.drawOval(
      Rect.fromLTWH(0, h * 0.7, w * 0.5, h * 0.3),
      paint,
    );

    // Stem.
    final stem = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08;
    canvas.drawLine(Offset(w * 0.45, h * 0.7), Offset(w * 0.45, h * 0.1), stem);

    // Flag.
    final flag = Path()
      ..moveTo(w * 0.45, h * 0.1)
      ..quadraticBezierTo(w * 0.8, h * 0.2, w * 0.7, h * 0.45);
    canvas.drawPath(flag, paint);
  }

  @override
  bool shouldRepaint(covariant _MusicNotePainter oldDelegate) =>
      oldDelegate.color != color;
}

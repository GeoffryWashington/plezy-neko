import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'neko_decor.dart';

/// A calm idle catgirl mascot that appears on neko-themed screens.
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
    with TickerProviderStateMixin {
  static const String _idleFrame = 'assets/neko/idle.png';
  static const String _blinkFrame = 'assets/neko/idle_blink.png';
  static const String _happy0 = 'assets/neko/happy_0.png';
  static const String _happy1 = 'assets/neko/happy_1.png';

  late final AnimationController _idle;
  late final AnimationController _happy;

  final math.Random _random = math.Random();

  Timer? _blinkTimer;
  Timer? _blinkShowTimer;
  Timer? _blinkDoubleTimer;
  Timer? _reducedMotionTimer;

  bool _isBlinking = false;
  bool _isHappy = false;

  (double, double)? _lastPrecached;

  ImageProvider _provider(String path, BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final h = (widget.height * dpr).round().clamp(1, 640);
    return ResizeImage(AssetImage(path), height: h, allowUpscaling: false);
  }

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _happy = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybePrecache();
    _scheduleBlink();
  }

  void _maybePrecache() {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final key = (widget.height, dpr);
    if (_lastPrecached == key) return;
    _lastPrecached = key;
    for (final path in [_idleFrame, _blinkFrame, _happy0, _happy1]) {
      precacheImage(_provider(path, context), context);
    }
  }

  @override
  void didUpdateWidget(covariant NekoMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.height != widget.height) {
      _maybePrecache();
    }
    if (oldWidget.dancing != widget.dancing) {
      if (widget.dancing) {
        _scheduleBlink();
      } else {
        _cancelBlinkTimers();
      }
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _blinkShowTimer?.cancel();
    _blinkDoubleTimer?.cancel();
    _reducedMotionTimer?.cancel();
    _idle.dispose();
    _happy.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Blink scheduling
  // ---------------------------------------------------------------------------

  void _cancelBlinkTimers() {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    _blinkShowTimer?.cancel();
    _blinkShowTimer = null;
    _blinkDoubleTimer?.cancel();
    _blinkDoubleTimer = null;
  }

  void _scheduleBlink() {
    if (_blinkTimer != null) return;
    if (!widget.dancing) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) return;
    if (_isHappy) return;

    final delay = Duration(
      milliseconds: 2400 + _random.nextInt(3101), // 2400–5500 ms
    );
    _blinkTimer = Timer(delay, _doBlink);
  }

  void _doBlink() {
    if (!mounted) return;
    if (_isHappy) return;

    setState(() => _isBlinking = true);
    _blinkShowTimer = Timer(const Duration(milliseconds: 130), () {
      if (!mounted) return;
      setState(() => _isBlinking = false);

      // 20 % chance of a double blink.
      if (_random.nextDouble() < 0.2) {
        _blinkDoubleTimer = Timer(const Duration(milliseconds: 180), () {
          if (!mounted) return;
          setState(() => _isBlinking = true);
          _blinkShowTimer = Timer(const Duration(milliseconds: 130), () {
            if (!mounted) return;
            setState(() => _isBlinking = false);
            _scheduleBlink();
          });
        });
      } else {
        _scheduleBlink();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Happy reaction
  // ---------------------------------------------------------------------------

  void _cheer() {
    _cancelBlinkTimers();

    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) == true;
    if (!widget.dancing || reducedMotion) {
      _reducedMotionTimer?.cancel();
      setState(() => _isHappy = true);
      _reducedMotionTimer = Timer(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        setState(() => _isHappy = false);
      });
      return;
    }

    setState(() => _isHappy = true);
    _happy
      ..removeStatusListener(_onHappyStatus)
      ..stop()
      ..value = 0
      ..forward()
      ..addStatusListener(_onHappyStatus);
  }

  void _onHappyStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!mounted) return;
    setState(() => _isHappy = false);
    _happy.value = 0;
    _happy.removeStatusListener(_onHappyStatus);
    _scheduleBlink();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final decor = nekoDecor(context);
    if (decor == null) {
      return const SizedBox.shrink();
    }

    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) == true;
    final animate = widget.dancing && !reducedMotion;

    final width = widget.height * 402 / 640;
    final totalHeight = widget.height + widget.height * 0.05;

    return Semantics(
      button: true,
      label: 'Neko mascot',
      onTap: _cheer,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _cheer,
          behavior: HitTestBehavior.opaque,
          child: RepaintBoundary(
            child: SizedBox(
              width: width,
              height: totalHeight,
              child: animate ? _buildAnimated(decor) : _buildStatic(decor),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Static (non-dancing / reduced-motion)
  // ---------------------------------------------------------------------------

  Widget _buildStatic(NekoDecor decor) {
    final frame = _isHappy ? _happy0 : _idleFrame;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        Positioned(
          bottom: 0,
          child: CustomPaint(
            size: Size(widget.height * 0.40, widget.height * 0.05),
            painter: _OvalShadowPainter(
              color: decor.cocoa.withValues(alpha: 0.16),
            ),
          ),
        ),
        Image(
          image: _provider(frame, context),
          height: widget.height,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Animated (idle bob + blinks + happy reaction)
  // ---------------------------------------------------------------------------

  Widget _buildAnimated(NekoDecor decor) {
    return AnimatedBuilder(
      animation: Listenable.merge([_idle, _happy]),
      builder: (context, _) {
        final v = _idle.value;
        final happyActive = _isHappy && _happy.isAnimating;
        final t = _happy.value;

        // Determine which frame to show.
        String frame;
        if (happyActive) {
          final idx = (t * 1400 / 175).floor() % 2;
          frame = idx == 0 ? _happy0 : _happy1;
        } else {
          frame = _isBlinking ? _blinkFrame : _idleFrame;
        }

        // Vertical offset.
        double yOffset;
        if (happyActive) {
          // Two hops: -height * 0.07 * |sin(2π·t)|
          yOffset =
              -widget.height * 0.07 * math.sin(2 * math.pi * t).abs();
        } else {
          // Idle bob: -(sin(2π·v) * 0.5 + 0.5) * height * 0.018
          yOffset =
              -(math.sin(2 * math.pi * v) * 0.5 + 0.5) *
              widget.height *
              0.018;
        }

        // Squash / stretch.
        double scaleY;
        double scaleX;
        if (happyActive) {
          // Pop scale: 1 → 1.06 → 1 over the first 300 ms.
          const popEnd = 300.0 / 1400.0;
          if (t < popEnd) {
            final popT = t / popEnd;
            final scale = popT < 0.5
                ? 1 + 0.06 * Curves.easeOut.transform(popT * 2)
                : 1 + 0.06 * (1 - Curves.easeIn.transform((popT - 0.5) * 2));
            scaleY = scale;
            scaleX = scale;
          } else {
            scaleY = 1.0;
            scaleX = 1.0;
          }
        } else {
          scaleY = 1 + 0.012 * math.sin(2 * math.pi * v + math.pi / 2);
          scaleX = 2 - scaleY;
        }

        // Shadow shrinks slightly as she rises.
        final maxBounce = happyActive
            ? widget.height * 0.07
            : widget.height * 0.018;
        final shadowScale =
            1.0 - (yOffset.abs() / maxBounce) * 0.15;
        final shadowColor = decor.cocoa.withValues(alpha: 0.16);

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
                  size: Size(widget.height * 0.40, widget.height * 0.05),
                  painter: _OvalShadowPainter(color: shadowColor),
                ),
              ),
            ),
            // Mascot.
            Transform.translate(
              offset: Offset(0, yOffset),
              child: Transform.scale(
                scaleX: scaleX,
                scaleY: scaleY,
                alignment: Alignment.bottomCenter,
                child: Image(
                  image: _provider(frame, context),
                  height: widget.height,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
            // Hearts / music notes during the happy reaction.
            if (widget.showHearts && happyActive)
              Positioned.fill(
                child: CustomPaint(
                  painter: _HeartsBurstPainter(
                    t: t,
                    height: widget.height,
                    width: widget.height * 402 / 640,
                    accent: decor.accent,
                    lavender: decor.lavender,
                  ),
                ),
              ),
          ],
        );
      },
    );
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

class _HeartsBurstPainter extends CustomPainter {
  final double t;
  final double height;
  final double width;
  final Color accent;
  final Color lavender;

  const _HeartsBurstPainter({
    required this.t,
    required this.height,
    required this.width,
    required this.accent,
    required this.lavender,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const count = 8; // 6 hearts + 2 music notes

    // Start position: near her head (top-centre of the image area).
    final headX = size.width / 2;
    final headY = size.height - height + height * 0.08;

    // Rise and fade driven by [t].
    final rise = height * 0.45 * t;
    final opacity = 1.0 - t;

    for (var i = 0; i < count; i++) {
      // Deterministic fan angles from −50° to +50°.
      final angleDeg = -50.0 + (100.0 / (count - 1)) * i;
      final angleRad = angleDeg * math.pi / 180;

      final spread = width * 0.35;
      final dx = math.sin(angleRad) * spread * t;
      final dy = -rise;

      final x = headX + dx;
      final y = headY + dy;

      final isHeart = i < 6;
      final baseColor = i.isEven ? accent : lavender;
      final color = baseColor.withValues(alpha: opacity);

      if (isHeart) {
        _drawHeart(canvas, x, y, height * 0.06, color);
      } else {
        _drawNote(canvas, x, y, height * 0.07, color);
      }
    }
  }

  void _drawHeart(
    Canvas canvas,
    double cx,
    double cy,
    double size,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size;
    final h = size;
    final path = Path()
      ..moveTo(cx, cy + h / 2)
      ..arcTo(
        Rect.fromLTWH(cx - w / 2, cy - h / 2, w / 2, h * 0.7),
        math.pi,
        math.pi,
        false,
      )
      ..arcTo(
        Rect.fromLTWH(cx, cy - h / 2, w / 2, h * 0.7),
        math.pi,
        math.pi,
        true,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawNote(
    Canvas canvas,
    double cx,
    double cy,
    double size,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size;
    final h = size;

    // Filled oval (note head).
    canvas.drawOval(
      Rect.fromLTWH(cx - w * 0.25, cy + h * 0.2, w * 0.5, h * 0.3),
      paint,
    );

    // Stem.
    final stem = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08;
    canvas.drawLine(
      Offset(cx + w * 0.2, cy + h * 0.2),
      Offset(cx + w * 0.2, cy - h * 0.3),
      stem,
    );

    // Flag.
    final flag = Path()
      ..moveTo(cx + w * 0.2, cy - h * 0.3)
      ..quadraticBezierTo(cx + w * 0.5, cy - h * 0.2, cx + w * 0.4, cy);
    canvas.drawPath(flag, paint);
  }

  @override
  bool shouldRepaint(covariant _HeartsBurstPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.accent != accent ||
      oldDelegate.lavender != lavender;
}

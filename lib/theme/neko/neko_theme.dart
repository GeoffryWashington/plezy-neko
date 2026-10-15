import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../gapped_track_shape.dart';
import '../mono_tokens.dart';
import 'neko_decor.dart';

final Map<({bool dark, TargetPlatform platform}), ThemeData> _nekoThemeCache = {};

ThemeData nekoTheme({required bool dark}) {
  final key = (dark: dark, platform: defaultTargetPlatform);
  final cached = _nekoThemeCache[key];
  if (cached != null) return cached;

  final theme = _buildNekoTheme(dark: dark, platform: key.platform);
  _nekoThemeCache[key] = theme;
  return theme;
}

ThemeData _buildNekoTheme({required bool dark, required TargetPlatform platform}) {
  final ({Color bg, Color surface, Color text, Color textMuted, Color outline, Color accent, Color onAccent, Color accentSoft, Color lavender, Color mint, Color cocoa, Color cream, Color error}) c;
  if (dark) {
    c = (
      bg: const Color(0xFF1D1320),
      surface: const Color(0xFF2A1B2E),
      text: const Color(0xFFFFE8F1),
      textMuted: const Color(0xFFFFE8F1).withValues(alpha: 0.62),
      outline: const Color(0xFFFF8FC1).withValues(alpha: 0.22),
      accent: const Color(0xFFFF8FC1),
      onAccent: const Color(0xFF2A1020),
      accentSoft: const Color(0xFF4A2440),
      lavender: const Color(0xFFB9A2E8),
      mint: const Color(0xFF7FCBB0),
      cocoa: const Color(0xFFC79A86),
      cream: const Color(0xFF3A2A35),
      error: const Color(0xFFFF6B81),
    );
  } else {
    c = (
      bg: const Color(0xFFFFF3F7),
      surface: const Color(0xFFFFFFFF),
      text: const Color(0xFF4A2C3A),
      textMuted: const Color(0xFF4A2C3A).withValues(alpha: 0.62),
      outline: const Color(0xFFF2C4D6),
      accent: const Color(0xFFD63F7A),
      onAccent: const Color(0xFFFFFFFF),
      accentSoft: const Color(0xFFFFD6E7),
      lavender: const Color(0xFFB9A2E8),
      mint: const Color(0xFF9FDDC6),
      cocoa: const Color(0xFF6B4434),
      cream: const Color(0xFFFFF8EC),
      error: const Color(0xFFE5484D),
    );
  }

  final bg = c.bg;
  final surface = c.surface;
  final text = c.text;
  final textMuted = c.textMuted;
  final outline = c.outline;
  final accent = c.accent;
  final onAccent = c.onAccent;
  final accentSoft = c.accentSoft;
  final lavender = c.lavender;
  final cocoa = c.cocoa;

  final clickableCursor = WidgetStateProperty.resolveWith<MouseCursor>(
    (states) => states.contains(WidgetState.disabled) ? MouseCursor.defer : SystemMouseCursors.click,
  );

  final buttonStyle = ButtonStyle(
    mouseCursor: clickableCursor,
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
    elevation: const WidgetStatePropertyAll(0),
    shadowColor: WidgetStatePropertyAll(cocoa.withValues(alpha: 0.18)),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled) ? text.withValues(alpha: 0.12) : accent,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled) ? text.withValues(alpha: 0.38) : onAccent,
    ),
    shape: const WidgetStatePropertyAll(StadiumBorder()),
  );

  final base = ThemeData(
    platform: platform,
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    fontFamilyFallback: platform == TargetPlatform.linux ? const ['Go Noto Current', 'Go Noto Current Hangul'] : null,
    colorScheme: ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: accentSoft,
      onPrimaryContainer: text,
      secondary: accent,
      onSecondary: onAccent,
      secondaryContainer: accentSoft,
      onSecondaryContainer: text,
      tertiary: lavender,
      onTertiary: const Color(0xFF2A1B2E),
      surface: surface,
      onSurface: text,
      surfaceContainerHighest: accentSoft.withValues(alpha: 0.6),
      surfaceContainerLow: bg,
      surfaceDim: bg,
      surfaceBright: surface,
      outline: outline,
      shadow: cocoa.withValues(alpha: 0.18),
      scrim: Colors.black,
      inverseSurface: text,
      onInverseSurface: bg,
      inversePrimary: bg,
      error: c.error,
      onError: Colors.white,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    focusColor: accent.withValues(alpha: 0.22),
    hoverColor: accent.withValues(alpha: 0.08),
    dividerColor: outline,
    scaffoldBackgroundColor: bg,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: text,
      titleTextStyle: TextStyle(color: accent, fontSize: 18, fontWeight: .w800, letterSpacing: 0.2),
    ),
    textTheme: Typography.englishLike2021
        .apply(bodyColor: text, displayColor: text)
        .copyWith(
          displayLarge: const TextStyle(fontWeight: .w800, letterSpacing: 0.2),
          titleMedium: const TextStyle(fontWeight: .w800, letterSpacing: 0.2),
          bodyMedium: TextStyle(color: text),
          bodySmall: TextStyle(color: textMuted),
        ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: .zero,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(22))),
    ),
    inputDecorationTheme: _nekoInputDecorationTheme(text, textMuted, accent),
    elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    textButtonTheme: TextButtonThemeData(style: ButtonStyle(mouseCursor: clickableCursor)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: ButtonStyle(mouseCursor: clickableCursor)),
    iconButtonTheme: IconButtonThemeData(style: ButtonStyle(mouseCursor: clickableCursor)),
    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      inactiveTrackColor: accent.withValues(alpha: 0.18),
      thumbColor: accent,
      trackHeight: 16,
      trackGap: 6,
      thumbSize: const WidgetStatePropertyAll(Size(4, 20)),
      thumbShape: const HandleThumbShape(),
      trackShape: const GappedTrackShape(),
      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2),
      // ignore: deprecated_member_use — opting into the 2024 slider appearance until the default flips
      year2023: false,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      circularTrackColor: accent.withValues(alpha: 0.15),
      linearTrackColor: accent.withValues(alpha: 0.15),
    ),
    dividerTheme: DividerThemeData(space: 0, thickness: 1, color: outline),
    listTileTheme: ListTileThemeData(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      iconColor: text,
      textColor: text,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: bg,
      elevation: 0,
      indicatorColor: accentSoft,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final active = states.contains(WidgetState.selected);
        return TextStyle(color: active ? text : text.withValues(alpha: 0.6), fontSize: 11);
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final active = states.contains(WidgetState.selected);
        return IconThemeData(size: 22, color: active ? accent : text.withValues(alpha: 0.6));
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: surface,
      contentTextStyle: TextStyle(color: text),
      actionTextColor: text,
      elevation: 6,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
      insetPadding: const EdgeInsets.all(16),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: outline),
      shape: StadiumBorder(side: BorderSide(color: outline)),
      selectedColor: accentSoft,
      checkmarkColor: accent,
      labelStyle: TextStyle(color: text),
      backgroundColor: surface,
    ),
  );

  return base.copyWith(
    extensions: [
      MonoTokens(
        radiusXs: 8,
        radiusSm: 12,
        radiusMd: 18,
        radiusLg: 26,
        groupGap: 3,
        space: 12,
        fast: const Duration(milliseconds: 140),
        normal: const Duration(milliseconds: 240),
        slow: const Duration(milliseconds: 360),
        expressive: const Duration(milliseconds: 420),
        bg: bg,
        surface: surface,
        outline: outline,
        text: text,
        textMuted: textMuted,
      ),
      NekoDecor(
        enabled: true,
        accent: accent,
        accentSoft: accentSoft,
        lavender: lavender,
        mint: c.mint,
        cocoa: cocoa,
        cream: c.cream,
        text: text,
      ),
    ],
  );
}

InputDecorationTheme _nekoInputDecorationTheme(Color text, Color textMuted, Color accent) {
  final unfocusedFill = accent.withValues(alpha: 0.08);
  final focusedFill = accent.withValues(alpha: 0.16);
  const border = OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16)), borderSide: BorderSide.none);
  return InputDecorationTheme(
    filled: true,
    fillColor: WidgetStateColor.resolveWith(
      (states) => states.contains(WidgetState.focused) ? focusedFill : unfocusedFill,
    ),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: border,
    enabledBorder: border,
    focusedBorder: border,
    hintStyle: TextStyle(color: textMuted),
  );
}

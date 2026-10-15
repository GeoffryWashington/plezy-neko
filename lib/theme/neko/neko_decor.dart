import 'package:flutter/material.dart';

/// Returns the [NekoDecor] extension from the current theme, or `null` when
/// the theme is not a Neko theme (or the extension is disabled).
///
/// Decoration widgets call this and render their child / nothing when `null`,
/// so mono themes see zero behaviour change.
NekoDecor? nekoDecor(BuildContext context) {
  final decor = Theme.of(context).extension<NekoDecor>();
  return decor?.enabled == true ? decor : null;
}

@immutable
class NekoDecor extends ThemeExtension<NekoDecor> {
  final bool enabled;
  final Color accent;
  final Color accentSoft;
  final Color lavender;
  final Color mint;
  final Color cocoa;
  final Color cream;
  final Color text;

  const NekoDecor({
    required this.enabled,
    required this.accent,
    required this.accentSoft,
    required this.lavender,
    required this.mint,
    required this.cocoa,
    required this.cream,
    required this.text,
  });

  @override
  NekoDecor copyWith({
    bool? enabled,
    Color? accent,
    Color? accentSoft,
    Color? lavender,
    Color? mint,
    Color? cocoa,
    Color? cream,
    Color? text,
  }) => NekoDecor(
    enabled: enabled ?? this.enabled,
    accent: accent ?? this.accent,
    accentSoft: accentSoft ?? this.accentSoft,
    lavender: lavender ?? this.lavender,
    mint: mint ?? this.mint,
    cocoa: cocoa ?? this.cocoa,
    cream: cream ?? this.cream,
    text: text ?? this.text,
  );

  @override
  ThemeExtension<NekoDecor> lerp(covariant NekoDecor? other, double t) {
    if (other == null) return this;
    Color lerpC(Color a, Color b) => Color.lerp(a, b, t)!;
    return NekoDecor(
      enabled: t < 0.5 ? this.enabled : other.enabled,
      accent: lerpC(accent, other.accent),
      accentSoft: lerpC(accentSoft, other.accentSoft),
      lavender: lerpC(lavender, other.lavender),
      mint: lerpC(mint, other.mint),
      cocoa: lerpC(cocoa, other.cocoa),
      cream: lerpC(cream, other.cream),
      text: lerpC(text, other.text),
    );
  }
}

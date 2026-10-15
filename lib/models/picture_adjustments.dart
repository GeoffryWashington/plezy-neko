import 'package:flutter/foundation.dart';

import '../mpv/mpv.dart';

@immutable
class PictureAdjustments {
  const PictureAdjustments({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.gamma = 0,
    this.hue = 0,
    this.sharpness = 0,
  });

  static const neutral = PictureAdjustments();

  final int brightness;
  final int contrast;
  final int saturation;
  final int gamma;
  final int hue;
  final int sharpness;

  bool get isNeutral =>
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      gamma == 0 &&
      hue == 0 &&
      sharpness == 0;

  PictureAdjustments copyWith({
    int? brightness,
    int? contrast,
    int? saturation,
    int? gamma,
    int? hue,
    int? sharpness,
  }) {
    return PictureAdjustments(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      gamma: gamma ?? this.gamma,
      hue: hue ?? this.hue,
      sharpness: sharpness ?? this.sharpness,
    );
  }

  Map<String, int> toJson() => {
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'gamma': gamma,
        'hue': hue,
        'sharpness': sharpness,
      };

  factory PictureAdjustments.fromJson(Object? json) {
    if (json is! Map) return neutral;
    return PictureAdjustments(
      brightness: _clamp(json['brightness']),
      contrast: _clamp(json['contrast']),
      saturation: _clamp(json['saturation']),
      gamma: _clamp(json['gamma']),
      hue: _clamp(json['hue']),
      sharpness: _clampSharpness(json['sharpness']),
    );
  }

  static int _clamp(Object? value) {
    final v = value is int ? value : (value is num ? value.toInt() : 0);
    return v.clamp(-100, 100);
  }

  static int _clampSharpness(Object? value) {
    final v = value is int ? value : (value is num ? value.toInt() : 0);
    return v.clamp(0, 100);
  }

  /// Apply the five mpv picture-adjustment properties to [player].
  /// Each property is set in its own try/catch so one failure does not
  /// prevent the others from being applied.
  Future<void> applyTo(Player player) async {
    const props = [
      ('brightness', 'brightness'),
      ('contrast', 'contrast'),
      ('saturation', 'saturation'),
      ('gamma', 'gamma'),
      ('hue', 'hue'),
    ];
    for (final (name, _) in props) {
      try {
        await player.setProperty(name, _valueFor(name).toString());
      } catch (_) {}
    }
  }

  int _valueFor(String name) => switch (name) {
        'brightness' => brightness,
        'contrast' => contrast,
        'saturation' => saturation,
        'gamma' => gamma,
        'hue' => hue,
        _ => 0,
      };

  @override
  bool operator ==(Object other) =>
      other is PictureAdjustments &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation &&
      other.gamma == gamma &&
      other.hue == hue;

  @override
  int get hashCode => Object.hash(brightness, contrast, saturation, gamma, hue);
}

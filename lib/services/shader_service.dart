import 'dart:io';

import '../models/picture_adjustments.dart';
import '../models/shader_preset.dart';
import '../mpv/player/player.dart';
import '../utils/app_logger.dart';
import 'ambient_lighting_service.dart';
import 'shader_asset_loader.dart';
import 'settings_service.dart';

/// Service for applying GLSL shaders to the MPV video player.
///
/// Handles shader chain building, HDR detection, and runtime switching.
/// When ambient lighting is active, the ambient lighting shader is always appended last
/// in the chain after any upscaling/processing shaders.
class ShaderService {
  final Player _player;

  /// Set when the last preset application failed (e.g. VSR unavailable).
  String? lastError;

  /// The preset in mpv's chain. Differs from [_requestedPreset] only while
  /// NVScaler is auto-skipped on HDR content.
  ShaderPreset _currentPreset = ShaderPreset.none;

  /// The preset the caller last asked for; what [reapplyForContent]
  /// re-decides against the picture mpv actually presents.
  ShaderPreset _requestedPreset = ShaderPreset.none;

  /// Reference to ambient lighting service for re-appending its shader after chain rebuilds.
  AmbientLightingService? ambientLightingService;

  int _sharpness = 0;
  List<String> _sharpenPaths = const [];

  ShaderService(this._player);

  /// The preset applied to the chain — none while NVScaler is auto-skipped.
  ShaderPreset get currentPreset => _currentPreset;

  static bool get isPlatformSupported => !Platform.isIOS;

  /// Check if the player is MPV (shaders are MPV-only)
  bool get isSupported => _player.playerType == 'mpv' && isPlatformSupported;

  /// Persist and apply live picture adjustments (brightness, contrast, ...).
  Future<void> applyPictureAdjustments(PictureAdjustments adj) async {
    await SettingsService.instance.write(SettingsService.pictureAdjustments, adj);
    await adj.applyTo(_player);
    await setSharpness(adj.sharpness);
  }

  /// Apply a shader preset to the video player.
  ///
  /// For NVScaler with auto-HDR skip enabled, will check video colorspace
  /// and skip shader application for HDR content. That check reads the
  /// decoded picture, so a call before the item's first frame (the start
  /// flow, an in-place swap) decides on stale or absent params;
  /// [reapplyForContent] settles it once a frame exists.
  Future<void> applyPreset(ShaderPreset preset) async {
    lastError = null;
    if (!isSupported) {
      appLogger.d('ShaderService: Shaders not supported on ${_player.playerType}');
      return;
    }

    _requestedPreset = preset;
    try {
      if (_skipsOnHdr(preset) && await _isHdrContent()) {
        appLogger.d('ShaderService: Skipping NVScaler on HDR content');
        await _applyChain(ShaderPreset.none);
        return;
      }
      await _applyChain(preset);
    } catch (e, st) {
      appLogger.w('ShaderService: Failed to apply preset', error: e, stackTrace: st);
      // Don't rethrow - shader failure shouldn't stop playback
    }
  }

  /// Re-decide the requested preset against the picture now decoded. Only
  /// an HDR-skipping NVScaler request depends on the content; anything else
  /// is a no-op. Returns whether the applied preset changed.
  Future<bool> reapplyForContent() async {
    final requested = _requestedPreset;
    if (!isSupported || !_skipsOnHdr(requested)) return false;

    try {
      final target = await _isHdrContent() ? ShaderPreset.none : requested;
      if (target == _currentPreset) return false;
      appLogger.d(
        target.isEnabled
            ? 'ShaderService: Applying ${requested.name}, content is SDR'
            : 'ShaderService: Skipping ${requested.name} on HDR content',
      );
      await _applyChain(target);
      return true;
    } catch (e, st) {
      appLogger.w('ShaderService: Failed to re-apply preset for content', error: e, stackTrace: st);
      return false;
    }
  }

  static bool _skipsOnHdr(ShaderPreset preset) =>
      preset.type == ShaderPresetType.nvscaler && preset.nvscalerConfig?.autoHdrSkip == true;

  bool _vsrFilterActive = false;

  /// Rebuild mpv's chain for [preset]: clear, append its shaders, keep
  /// ambient lighting last.
  Future<void> _applyChain(ShaderPreset preset) async {
    final shaderPaths = await ShaderAssetLoader.getShadersForPreset(preset);

    await _clearShaders();
    for (final shaderPath in shaderPaths) {
      await _player.command(['change-list', 'glsl-shaders', 'append', shaderPath]);
    }

    if (preset.type == ShaderPresetType.nvidiaVsr) {
      await _applyNvidiaVsr();
    }

    _currentPreset = preset;

    // Re-append sharpen shaders if active (they were cleared above).
    if (_sharpness > 0) {
      _sharpenPaths = const [];
      await setSharpness(_sharpness);
    }

    // Re-append ambient lighting shader at end of chain
    await _reappendAmbientLighting();

    if (shaderPaths.isNotEmpty) {
      appLogger.d('ShaderService: Applied ${preset.name} with ${shaderPaths.length} shaders');
    }
  }

  /// Apply NVIDIA RTX Video Super Resolution as a labeled video filter.
  Future<void> _applyNvidiaVsr() async {
    const vsrErrorMessage =
        "RTX Video Super Resolution isn't available here (it needs an NVIDIA RTX GPU and hardware decoding).";

    // Compute scale: clamp(osdHeight / videoHeight, 1.0, 4.0), rounded to 1 decimal.
    double scale = 2.0;
    try {
      final osdHeightRaw = await _player.getProperty('osd-height');
      final videoHeightRaw = await _player.getProperty('video-params/h');
      final osd = double.tryParse(osdHeightRaw?.toString() ?? '');
      final video = double.tryParse(videoHeightRaw?.toString() ?? '');
      if (osd != null && video != null && video > 0) {
        scale = (osd / video).clamp(1.0, 4.0);
        scale = (scale * 10).roundToDouble() / 10;
      }
    } catch (_) {
      scale = 2.0;
    }

    try {
      await _player.command(['vf', 'add', '@nekovsr:d3d11vpp=scaling-mode=nvidia:scale=$scale']);
      _vsrFilterActive = true;
    } catch (e, st) {
      appLogger.w('ShaderService: Failed to add VSR filter', error: e, stackTrace: st);
      lastError = vsrErrorMessage;
      return;
    }

    // Verify the filter actually took effect.
    await Future.delayed(const Duration(milliseconds: 1500));
    try {
      final vf = await _player.getProperty('vf');
      if (vf == null || !vf.toString().contains('nekovsr')) {
        try {
          await _player.command(['vf', 'remove', '@nekovsr']);
        } catch (_) {}
        _vsrFilterActive = false;
        lastError = vsrErrorMessage;
        appLogger.w('ShaderService: VSR filter not active after apply');
      }
    } catch (e, st) {
      appLogger.w('ShaderService: Failed to verify VSR filter', error: e, stackTrace: st);
      lastError = vsrErrorMessage;
    }
  }

  Future<void> _clearShaders() async {
    try {
      await _player.command(['change-list', 'glsl-shaders', 'clr', '']);
    } catch (e, st) {
      appLogger.w('ShaderService: Failed to clear shaders', error: e, stackTrace: st);
    }
    // Remove the VSR video filter if present (ignore failure).
    if (_vsrFilterActive) {
      try {
        await _player.command(['vf', 'remove', '@nekovsr']);
      } catch (_) {}
      _vsrFilterActive = false;
    }
  }

  /// Re-append the ambient lighting shader if it's active.
  /// Called after shader chain rebuilds to keep ambient lighting last.
  Future<void> _reappendAmbientLighting() async {
    final service = ambientLightingService;
    if (service == null || !service.isEnabled) return;

    try {
      await service.reappendShader();
    } catch (e, st) {
      appLogger.w('ShaderService: Failed to re-append ambient lighting', error: e, stackTrace: st);
    }
  }

  /// Check if the current video content is HDR.
  Future<bool> _isHdrContent() async {
    try {
      // Check video color matrix for BT.2020 (HDR indicator)
      final colormatrix = await _player.getProperty('video-params/colormatrix');
      if (colormatrix?.contains('bt.2020') == true) {
        return true;
      }

      // Also check color primaries
      final primaries = await _player.getProperty('video-params/primaries');
      if (primaries?.contains('bt.2020') == true) {
        return true;
      }

      // Check for HDR transfer characteristics
      final gamma = await _player.getProperty('video-params/gamma');
      if (gamma?.contains('pq') == true || gamma?.contains('hlg') == true) {
        return true;
      }

      return false;
    } catch (e) {
      appLogger.d('ShaderService: HDR detection failed', error: e);
      return false;
    }
  }

  /// Set the CAS sharpening level (0 = off, 1..100 = intensity).
  Future<void> setSharpness(int value) async {
    final clamped = value.clamp(0, 100);
    _sharpness = clamped;

    if (clamped == 0) {
      for (final p in _sharpenPaths) {
        try {
          await _player.command(['change-list', 'glsl-shaders', 'remove', p]);
        } catch (_) {}
      }
      _sharpenPaths = const [];
      return;
    }

    if (_sharpenPaths.isEmpty) {
      final paths = await ShaderAssetLoader.getSharpenShaders();
      for (final p in paths) {
        await _player.command(['change-list', 'glsl-shaders', 'append', p]);
      }
      _sharpenPaths = paths;
    }

    await _player.command([
      'change-list',
      'glsl-shader-opts',
      'set',
      'SHARPENING=${(clamped / 100).toStringAsFixed(2)}',
    ]);
  }

  /// Capture a before/after comparison screenshot of the current frame.
  /// Returns the file paths, or null on failure.
  Future<({String before, String after})?> captureComparison(String dir) async {
    final wasPaused = (await _player.getProperty('pause')) == 'yes';
    await _player.setProperty('pause', 'yes');

    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final after = '$dir/neko_cmp_after_$stamp.png';
      final before = '$dir/neko_cmp_before_$stamp.png';

      // Screenshot with enhancements on.
      await _player.command(['screenshot-to-file', after, 'window']);

      // Save current picture properties.
      final brightness = await _player.getProperty('brightness');
      final contrast = await _player.getProperty('contrast');
      final saturation = await _player.getProperty('saturation');
      final gamma = await _player.getProperty('gamma');
      final hue = await _player.getProperty('hue');

      // Turn enhancements off.
      await _player.command(['change-list', 'glsl-shaders', 'clr', '']);
      await _player.setProperty('brightness', '0');
      await _player.setProperty('contrast', '0');
      await _player.setProperty('saturation', '0');
      await _player.setProperty('gamma', '0');
      await _player.setProperty('hue', '0');
      await Future.delayed(const Duration(milliseconds: 180));

      // Screenshot without enhancements.
      await _player.command(['screenshot-to-file', before, 'window']);

      // Restore picture properties and shader chain.
      await _player.setProperty('brightness', brightness ?? '0');
      await _player.setProperty('contrast', contrast ?? '0');
      await _player.setProperty('saturation', saturation ?? '0');
      await _player.setProperty('gamma', gamma ?? '0');
      await _player.setProperty('hue', hue ?? '0');
      await _applyChain(_currentPreset);

      if (!wasPaused) {
        await _player.setProperty('pause', 'no');
      }

      // Best-effort cleanup of old comparison files.
      await _cleanupComparisonFiles(dir);

      return (before: before, after: after);
    } catch (e, st) {
      appLogger.w('ShaderService: captureComparison failed', error: e, stackTrace: st);
      try {
        await _applyChain(_currentPreset);
        if (!wasPaused) {
          await _player.setProperty('pause', 'no');
        }
      } catch (_) {}
      return null;
    }
  }

  /// Delete comparison files older than the newest 4.
  Future<void> _cleanupComparisonFiles(String dir) async {
    try {
      final directory = Directory(dir);
      if (!await directory.exists()) return;
      final entries = await directory.list().toList();
      final files = <(File, DateTime)>[];
      for (final e in entries) {
        if (e is File && e.path.contains('neko_cmp_')) {
          files.add((e, await e.lastModified()));
        }
      }
      if (files.length <= 4) return;
      files.sort((a, b) => b.$2.compareTo(a.$2));
      for (final (f, _) in files.skip(4)) {
        try {
          await f.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> disable() async {
    await applyPreset(ShaderPreset.none);
  }
}

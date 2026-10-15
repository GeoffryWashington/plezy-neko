import 'dart:async';
import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

/// Detects GPU capabilities that gate optional video features. Never throws.
class GpuInfo {
  static Future<bool>? _hasNvidiaRtx;

  /// Returns true if an NVIDIA RTX GPU is detected (Windows only).
  static Future<bool> hasNvidiaRtx() => _hasNvidiaRtx ??= _detect();

  static Future<bool> _detect() async {
    if (!Platform.isWindows) return false;
    const classPath =
        r'SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}';
    RegistryKey? classKey;
    try {
      classKey = Registry.openPath(RegistryHive.localMachine, path: classPath);
      for (final name in classKey.subkeyNames) {
        RegistryKey? subKey;
        try {
          subKey = Registry.openPath(
            RegistryHive.localMachine,
            path: '$classPath\\$name',
          );
          final desc = subKey.getStringValue('DriverDesc');
          if (desc != null) {
            final lower = desc.toLowerCase();
            if (lower.contains('nvidia') && lower.contains('rtx')) {
              return true;
            }
          }
        } catch (_) {
          // Skip subkeys that can't be opened or read (e.g. "Properties").
        } finally {
          subKey?.close();
        }
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      classKey?.close();
    }
  }
}

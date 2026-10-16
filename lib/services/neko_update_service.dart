import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/app_logger.dart';

/// Fork version. Bumped for every release; must equal the release tag minus the leading "v".
const kNekoVersion = '2.23.0-neko.2';
const kNekoRepo = 'GeoffryWashington/plezy-neko';

class NekoRelease {
  final String tag;
  final String version;
  final String notes;
  final String? setupUrl;
  final String htmlUrl;

  const NekoRelease({
    required this.tag,
    required this.version,
    required this.notes,
    this.setupUrl,
    required this.htmlUrl,
  });
}

/// Parses a Neko version string like `2.23.0-neko.2` (optionally with a
/// leading `v`) into `[major, minor, patch, neko]`. Returns `null` if the
/// string does not match the expected pattern.
List<int>? parseNekoVersion(String v) {
  final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)-neko\.(\d+)$').firstMatch(v);
  if (match == null) return null;
  return [
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
  ];
}

/// Returns `true` if [candidate] is strictly newer than [current].
/// Returns `false` if either string cannot be parsed.
bool isNewerNekoVersion(String candidate, String current) {
  final c = parseNekoVersion(candidate);
  final cur = parseNekoVersion(current);
  if (c == null || cur == null) return false;
  for (int i = 0; i < c.length; i++) {
    if (c[i] != cur[i]) return c[i] > cur[i];
  }
  return false; // equal
}

class NekoUpdateService extends ChangeNotifier {
  static final NekoUpdateService instance = NekoUpdateService._();

  static DateTime? _lastCheck;

  NekoRelease? _available;
  bool _isChecking = false;

  NekoRelease? get available => _available;
  bool get isChecking => _isChecking;

  NekoUpdateService._();

  /// Checks the GitHub API for a newer release. Never throws.
  Future<void> checkForUpdates({bool force = false}) async {
    if (!Platform.isWindows) return;

    if (!force && _lastCheck != null) {
      final elapsed = DateTime.now().difference(_lastCheck!);
      if (elapsed < const Duration(hours: 6)) return;
    }

    _isChecking = true;
    notifyListeners();

    try {
      final uri = Uri.parse('https://api.github.com/repos/$kNekoRepo/releases/latest');
      final response = await http
          .get(uri, headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'PlezyNeko/$kNekoVersion',
          })
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        appLogger.w('Neko update check: HTTP ${response.statusCode}');
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = data['tag_name'] as String? ?? '';
      final body = data['body'] as String? ?? '';
      final htmlUrl = data['html_url'] as String? ?? '';

      String? setupUrl;
      final assets = data['assets'] as List<dynamic>?;
      if (assets != null) {
        for (final asset in assets) {
          if (asset is Map<String, dynamic> && asset['name'] == 'plezy-neko-setup.exe') {
            setupUrl = asset['browser_download_url'] as String?;
            break;
          }
        }
      }

      final version = tag.startsWith('v') ? tag.substring(1) : tag;
      final release = NekoRelease(
        tag: tag,
        version: version,
        notes: body,
        setupUrl: setupUrl,
        htmlUrl: htmlUrl,
      );

      if (isNewerNekoVersion(tag, kNekoVersion)) {
        if (_available != release) {
          _available = release;
          notifyListeners();
        }
      } else {
        if (_available != null) {
          _available = null;
          notifyListeners();
        }
      }
    } catch (e) {
      appLogger.w('Neko update check failed: $e');
    } finally {
      _lastCheck = DateTime.now();
      _isChecking = false;
      notifyListeners();
    }
  }

  /// Downloads the installer and launches it silently. Throws on failure.
  /// If no installer URL is available (or not on Windows), opens the release
  /// page in the browser instead.
  Future<void> downloadAndInstall(
    NekoRelease r, {
    required void Function(double progress) onProgress,
  }) async {
    if (r.setupUrl == null || !Platform.isWindows) {
      await launchUrl(Uri.parse(r.htmlUrl), mode: LaunchMode.externalApplication);
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}\\plezy-neko-setup-${r.version}.exe';

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(r.setupUrl!));
      final streamedResponse = await client.send(request);
      if (streamedResponse.statusCode != 200) {
        throw Exception('Download failed (HTTP ${streamedResponse.statusCode})');
      }

      final contentLength = streamedResponse.contentLength;
      final file = File(filePath);
      try {
        final sink = file.openWrite();

        var received = 0;
        await for (final chunk in streamedResponse.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (contentLength != null && contentLength > 0) {
            onProgress(received / contentLength);
          }
        }
        await sink.close();

        final fileSize = file.lengthSync();
        if (fileSize < 1024 * 1024) {
          throw Exception('Downloaded file is too small ($fileSize bytes)');
        }

        final head = await file.openRead(0, 2).first;
        if (head[0] != 0x4D || head[1] != 0x5A) {
          throw Exception('Downloaded file is not a Windows installer');
        }

        await Process.start(
          filePath,
          ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
          mode: ProcessStartMode.detached,
        );

        exit(0);
      } catch (e) {
        try {
          await file.delete();
        } catch (_) {}
        rethrow;
      }
    } finally {
      client.close();
    }
  }
}

import 'dart:async';

import 'package:http/http.dart' as http;

/// Probes [url] with a single-byte range request and returns the HTTP status
/// code, or `null` on any error or timeout.
///
/// PMS answers HTTP 500/503 instead of a transcode decision when a remote
/// client exceeds its per-stream bandwidth cap. Official clients fall back
/// to a server transcode in that case. A failed probe (timeout, socket
/// error) must never block playback, so this function swallows all errors
/// and returns `null`.
Future<int?> probeHttpStatus(
  String url, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final client = http.Client();
  try {
    final request = http.Request('GET', Uri.parse(url))
      ..headers['Range'] = 'bytes=0-0';
    final streamedResponse = await client.send(request).timeout(timeout);
    return streamedResponse.statusCode;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

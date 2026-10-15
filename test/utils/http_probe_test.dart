import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/http_probe.dart';

void main() {
  group('probeHttpStatus', () {
    test('returns 500 when the server answers 500', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((request) async {
        expect(request.headers.value('Range'), 'bytes=0-0');
        request.response.statusCode = 500;
        await request.response.close();
      });

      final status = await probeHttpStatus('http://127.0.0.1:${server.port}/');
      expect(status, 500);
    });

    test('returns 206 when the server answers 206 with a 1-byte body', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((request) async {
        request.response.statusCode = 206;
        request.response.write('x');
        await request.response.close();
      });

      final status = await probeHttpStatus('http://127.0.0.1:${server.port}/');
      expect(status, 206);
    });

    test('returns null when nothing listens on the port', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close(force: true);

      final status = await probeHttpStatus('http://127.0.0.1:$port/');
      expect(status, isNull);
    });

    test('returns null on timeout', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      final heldResponses = <HttpResponse>[];
      server.listen((request) {
        // Never respond; hold the response open so the client times out.
        heldResponses.add(request.response);
      });

      addTearDown(() {
        for (final r in heldResponses) {
          r.close();
        }
      });

      final status = await probeHttpStatus(
        'http://127.0.0.1:${server.port}/',
        timeout: const Duration(milliseconds: 300),
      );
      expect(status, isNull);
    });
  });
}

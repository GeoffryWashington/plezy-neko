import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/neko_update_service.dart';

void main() {
  group('parseNekoVersion', () {
    test('parses standard neko version', () {
      expect(parseNekoVersion('2.23.0-neko.2'), [2, 23, 0, 2]);
    });

    test('parses version with v prefix', () {
      expect(parseNekoVersion('v2.23.0-neko.2'), [2, 23, 0, 2]);
    });

    test('returns null for non-neko version', () {
      expect(parseNekoVersion('2.23.0'), isNull);
    });

    test('returns null for garbage input', () {
      expect(parseNekoVersion('garbage'), isNull);
    });
  });

  group('isNewerNekoVersion', () {
    test('newer patch is true', () {
      expect(isNewerNekoVersion('2.23.0-neko.3', '2.23.0-neko.2'), isTrue);
    });

    test('equal versions is false', () {
      expect(isNewerNekoVersion('2.23.0-neko.2', '2.23.0-neko.2'), isFalse);
    });

    test('older patch is false', () {
      expect(isNewerNekoVersion('2.23.0-neko.1', '2.23.0-neko.2'), isFalse);
    });

    test('higher minor beats higher patch', () {
      expect(isNewerNekoVersion('2.24.0-neko.1', '2.23.0-neko.9'), isTrue);
    });

    test('double-digit major comparison', () {
      expect(isNewerNekoVersion('10.0.0-neko.1', '9.9.9-neko.9'), isTrue);
    });

    test('unparseable returns false', () {
      expect(isNewerNekoVersion('garbage', '2.23.0-neko.2'), isFalse);
      expect(isNewerNekoVersion('2.23.0-neko.2', 'garbage'), isFalse);
    });
  });
}

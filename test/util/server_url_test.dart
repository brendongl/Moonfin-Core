import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/server_url.dart';

void main() {
  group('normalizeServerBaseUrl', () {
    test('ignores a trailing slash', () {
      expect(
        normalizeServerBaseUrl('https://media.example.com/'),
        normalizeServerBaseUrl('https://media.example.com'),
      );
    });

    test('ignores a web client path suffix', () {
      expect(
        normalizeServerBaseUrl('https://media.example.com/web/index.html'),
        normalizeServerBaseUrl('https://media.example.com'),
      );
      expect(
        normalizeServerBaseUrl('https://media.example.com/web'),
        normalizeServerBaseUrl('https://media.example.com'),
      );
    });

    test('ignores an explicit default port', () {
      expect(
        normalizeServerBaseUrl('https://media.example.com:443'),
        normalizeServerBaseUrl('https://media.example.com'),
      );
      expect(
        normalizeServerBaseUrl('http://media.example.com:80'),
        normalizeServerBaseUrl('http://media.example.com'),
      );
    });

    test('ignores host casing', () {
      expect(
        normalizeServerBaseUrl('https://Media.Example.COM'),
        normalizeServerBaseUrl('https://media.example.com'),
      );
    });

    test('keeps a reverse proxy path prefix', () {
      expect(
        normalizeServerBaseUrl('https://example.com/jellyfin/'),
        'https://example.com/jellyfin',
      );
    });

    test('keeps a non-default port', () {
      expect(
        normalizeServerBaseUrl('http://192.168.1.5:8096/'),
        'http://192.168.1.5:8096',
      );
    });

    test('still separates genuinely different servers', () {
      expect(
        normalizeServerBaseUrl('https://media.example.com'),
        isNot(normalizeServerBaseUrl('http://192.168.1.5:8096')),
      );
    });
  });
}

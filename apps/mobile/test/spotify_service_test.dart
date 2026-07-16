import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:twistaway_app/integrations/spotify_service.dart';

class _MemoryStorage extends FlutterSecureStorage {
  _MemoryStorage(this.values);

  final Map<String, String> values;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

class _CancelledAppAuth extends FlutterAppAuth {
  const _CancelledAppAuth();

  @override
  Future<AuthorizationTokenResponse> authorizeAndExchangeCode(
    AuthorizationTokenRequest request,
  ) {
    throw FlutterAppAuthUserCancelledException(
      code: 'user_cancelled',
      platformErrorDetails: FlutterAppAuthPlatformErrorDetails(),
    );
  }
}

void main() {
  test('restores Spotify session and reads current playback', () async {
    final storage = _MemoryStorage({
      'spotify.accessToken': 'access-token',
      'spotify.refreshToken': 'refresh-token',
      'spotify.expiration':
          DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    });
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer access-token');
      expect(request.url.path, '/v1/me/player');
      return http.Response(
        jsonEncode({
          'is_playing': true,
          'device': {'name': 'Phone'},
          'actions': {
            'disallows': {
              'pausing': false,
              'skipping_next': true,
              'skipping_prev': false,
            },
          },
          'item': {
            'name': 'Shout at the Devil',
            'uri': 'spotify:track:example',
            'external_urls': {
              'spotify': 'https://open.spotify.com/track/example',
            },
            'artists': [
              {'name': 'Mötley Crüe'},
            ],
            'album': {
              'images': [
                {'url': 'https://example.test/cover.jpg'},
              ],
            },
          },
        }),
        200,
      );
    });
    final service = SpotifyService(storage: storage, client: client);

    await service.initialize();

    expect(service.state.connected, isTrue);
    expect(service.state.trackName, 'Shout at the Devil');
    expect(service.state.artistName, 'Mötley Crüe');
    expect(service.state.isPlaying, isTrue);
    expect(service.state.hasActiveDevice, isTrue);
    expect(service.state.spotifyUri, 'spotify:track:example');
    expect(
      service.state.spotifyUrl,
      'https://open.spotify.com/track/example',
    );
    expect(service.state.canTogglePlayback, isTrue);
    expect(service.state.canSkipNext, isFalse);
    expect(service.state.canSkipPrevious, isTrue);
    service.dispose();
  });

  test('restricted controls are blocked before Spotify receives a command',
      () async {
    var commandCount = 0;
    final storage = _MemoryStorage({
      'spotify.accessToken': 'access-token',
      'spotify.refreshToken': 'refresh-token',
      'spotify.expiration':
          DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    });
    final service = SpotifyService(
      storage: storage,
      client: MockClient((request) async {
        if (request.method != 'GET') commandCount += 1;
        return http.Response(
          jsonEncode({
            'is_playing': true,
            'device': {'name': 'Phone'},
            'actions': {
              'disallows': {'skipping_next': true},
            },
            'item': {'name': 'Nervous'},
          }),
          200,
        );
      }),
    );
    await service.initialize();

    await expectLater(
      service.next(),
      throwsA(
        isA<SpotifyException>().having(
          (error) => error.message,
          'message',
          contains('does not allow skipping forward'),
        ),
      ),
    );
    expect(commandCount, 0);
    service.dispose();
  });

  test('Spotify restriction responses are translated for the rider', () async {
    final storage = _MemoryStorage({
      'spotify.accessToken': 'access-token',
      'spotify.refreshToken': 'refresh-token',
      'spotify.expiration':
          DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    });
    final service = SpotifyService(
      storage: storage,
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'is_playing': true,
              'device': {'name': 'Phone'},
              'actions': {
                'disallows': {'skipping_next': false},
              },
              'item': {'name': 'Nervous'},
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'error': {'status': 403, 'message': 'Restriction violated'},
          }),
          403,
        );
      }),
    );
    await service.initialize();

    await expectLater(
      service.next(),
      throwsA(
        isA<SpotifyException>().having(
          (error) => error.message,
          'message',
          contains('Spotify restricted that control'),
        ),
      ),
    );
    service.dispose();
  });

  test('canceling account linking clears the busy state', () async {
    final service = SpotifyService(
      appAuth: const _CancelledAppAuth(),
      storage: _MemoryStorage({}),
      client: MockClient((_) async => http.Response('', 204)),
    );

    final connected = await service.connect();

    expect(connected, isFalse);
    expect(service.state.connected, isFalse);
    expect(service.state.busy, isFalse);
    service.dispose();
  });

  test('a missing active player returns a useful error and clears busy',
      () async {
    final storage = _MemoryStorage({
      'spotify.accessToken': 'access-token',
      'spotify.refreshToken': 'refresh-token',
      'spotify.expiration':
          DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    });
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'is_playing': false,
            'device': {'name': 'Phone'},
            'item': null,
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'error': {'status': 404, 'message': 'Player command failed'},
        }),
        404,
      );
    });
    final service = SpotifyService(storage: storage, client: client);
    await service.initialize();

    await expectLater(
      service.togglePlayback(),
      throwsA(
        isA<SpotifyException>().having(
          (error) => error.message,
          'message',
          contains('Open Spotify'),
        ),
      ),
    );
    expect(service.state.busy, isFalse);
    service.dispose();
  });

  test('malformed Spotify playback data is contained', () async {
    final storage = _MemoryStorage({
      'spotify.accessToken': 'access-token',
      'spotify.refreshToken': 'refresh-token',
      'spotify.expiration':
          DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    });
    final service = SpotifyService(
      storage: storage,
      client: MockClient((_) async => http.Response('not-json', 200)),
    );
    await service.initialize();

    await expectLater(
      service.refreshPlayback(),
      throwsA(
        isA<SpotifyException>().having(
          (error) => error.message,
          'message',
          contains('unreadable response'),
        ),
      ),
    );
    service.dispose();
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class SpotifyException implements Exception {
  const SpotifyException(this.message);

  final String message;

  @override
  String toString() => message;
}

@immutable
class SpotifyPlayerState {
  const SpotifyPlayerState({
    this.connected = false,
    this.busy = false,
    this.trackName,
    this.artistName,
    this.albumArtUrl,
    this.spotifyUri,
    this.spotifyUrl,
    this.isPlaying = false,
    this.hasActiveDevice = false,
    this.canPause = true,
    this.canResume = true,
    this.canSkipNext = false,
    this.canSkipPrevious = false,
  });

  final bool connected;
  final bool busy;
  final String? trackName;
  final String? artistName;
  final String? albumArtUrl;
  final String? spotifyUri;
  final String? spotifyUrl;
  final bool isPlaying;
  final bool hasActiveDevice;
  final bool canPause;
  final bool canResume;
  final bool canSkipNext;
  final bool canSkipPrevious;

  bool get canTogglePlayback => isPlaying ? canPause : canResume;

  SpotifyPlayerState copyWith({
    bool? connected,
    bool? busy,
    String? trackName,
    String? artistName,
    String? albumArtUrl,
    String? spotifyUri,
    String? spotifyUrl,
    bool? isPlaying,
    bool? hasActiveDevice,
    bool? canPause,
    bool? canResume,
    bool? canSkipNext,
    bool? canSkipPrevious,
    bool clearTrack = false,
  }) {
    return SpotifyPlayerState(
      connected: connected ?? this.connected,
      busy: busy ?? this.busy,
      trackName: clearTrack ? null : trackName ?? this.trackName,
      artistName: clearTrack ? null : artistName ?? this.artistName,
      albumArtUrl: clearTrack ? null : albumArtUrl ?? this.albumArtUrl,
      spotifyUri: clearTrack ? null : spotifyUri ?? this.spotifyUri,
      spotifyUrl: clearTrack ? null : spotifyUrl ?? this.spotifyUrl,
      isPlaying: isPlaying ?? this.isPlaying,
      hasActiveDevice: hasActiveDevice ?? this.hasActiveDevice,
      canPause: canPause ?? this.canPause,
      canResume: canResume ?? this.canResume,
      canSkipNext: canSkipNext ?? this.canSkipNext,
      canSkipPrevious: canSkipPrevious ?? this.canSkipPrevious,
    );
  }
}

class SpotifyService extends ChangeNotifier {
  SpotifyService({
    FlutterAppAuth appAuth = const FlutterAppAuth(),
    FlutterSecureStorage storage = const FlutterSecureStorage(),
    http.Client? client,
  })  : _appAuth = appAuth,
        _storage = storage,
        _client = client ?? http.Client();

  static const clientId = String.fromEnvironment(
    'SPOTIFY_CLIENT_ID',
    defaultValue: 'bd5c1eb0153747c59d9eec5ef3397367',
  );
  static const redirectUri = String.fromEnvironment(
    'SPOTIFY_REDIRECT_URI',
    defaultValue: 'twistaway-login://spotify-callback',
  );
  static const _authorizationEndpoint =
      'https://accounts.spotify.com/authorize';
  static const _tokenEndpoint = 'https://accounts.spotify.com/api/token';
  static const _apiBase = 'https://api.spotify.com/v1';
  static const _accessTokenKey = 'spotify.accessToken';
  static const _refreshTokenKey = 'spotify.refreshToken';
  static const _expirationKey = 'spotify.expiration';
  static const _scopes = <String>[
    'user-read-playback-state',
    'user-read-currently-playing',
    'user-modify-playback-state',
  ];
  static const _configuration = AuthorizationServiceConfiguration(
    authorizationEndpoint: _authorizationEndpoint,
    tokenEndpoint: _tokenEndpoint,
  );

  final FlutterAppAuth _appAuth;
  final FlutterSecureStorage _storage;
  final http.Client _client;
  ValueChanged<String>? onError;
  Timer? _pollTimer;
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiration;
  bool _disposed = false;
  String? _lastReportedError;
  DateTime? _lastErrorAt;
  SpotifyPlayerState _state = const SpotifyPlayerState();

  SpotifyPlayerState get state => _state;

  Future<void> initialize() async {
    try {
      final values = await Future.wait([
        _storage.read(key: _accessTokenKey),
        _storage.read(key: _refreshTokenKey),
        _storage.read(key: _expirationKey),
      ]);
      _accessToken = values[0];
      _refreshToken = values[1];
      _expiration = DateTime.tryParse(values[2] ?? '');
      if (_accessToken == null && _refreshToken == null) return;
      if (!await _ensureAccessToken()) {
        await disconnect();
        return;
      }
      _setState(_state.copyWith(connected: true));
      _startPolling();
      await refreshPlayback();
    } catch (_) {
      // Spotify remains optional when secure storage is unavailable.
    }
  }

  Future<bool> connect() async {
    if (kIsWeb) {
      throw const SpotifyException(
        'Spotify account linking is available in the Android and iPhone apps.',
      );
    }
    if (clientId.isEmpty) {
      throw const SpotifyException('Spotify Client ID is not configured.');
    }
    _setState(_state.copyWith(busy: true));
    try {
      final response = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientId,
          redirectUri,
          serviceConfiguration: _configuration,
          scopes: _scopes,
        ),
      );
      if (response.accessToken == null) {
        throw StateError('Spotify did not return an access token.');
      }
      await _saveTokens(
        accessToken: response.accessToken!,
        refreshToken: response.refreshToken,
        expiration: response.accessTokenExpirationDateTime,
      );
      _setState(_state.copyWith(connected: true, busy: false));
      _startPolling();
      try {
        await refreshPlayback();
      } catch (error, stackTrace) {
        _reportError(error, stackTrace);
      }
      return true;
    } on FlutterAppAuthUserCancelledException {
      _setState(_state.copyWith(busy: false));
      return false;
    } on FlutterAppAuthPlatformException catch (error, stackTrace) {
      _setState(_state.copyWith(busy: false));
      Error.throwWithStackTrace(
        SpotifyException(_appAuthErrorMessage(error)),
        stackTrace,
      );
    } catch (error, stackTrace) {
      _setState(_state.copyWith(busy: false));
      Error.throwWithStackTrace(_asSpotifyException(error), stackTrace);
    }
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _accessToken = null;
    _refreshToken = null;
    _expiration = null;
    try {
      await Future.wait([
        _storage.delete(key: _accessTokenKey),
        _storage.delete(key: _refreshTokenKey),
        _storage.delete(key: _expirationKey),
      ]);
    } catch (error, stackTrace) {
      _reportError(
        const SpotifyException(
          'Spotify was disconnected, but its saved session could not be fully cleared.',
        ),
        stackTrace,
        debugCause: error,
      );
    } finally {
      _setState(const SpotifyPlayerState());
    }
  }

  Future<void> refreshPlayback() async {
    if (!_state.connected) return;
    final response = await _send('GET', '/me/player');
    if (response.statusCode == 204) {
      _setState(
        _state.copyWith(
          busy: false,
          hasActiveDevice: false,
          isPlaying: false,
          canPause: false,
          canResume: false,
          canSkipNext: false,
          canSkipPrevious: false,
          clearTrack: true,
        ),
      );
      return;
    }
    _expectSuccess(response);
    final decoded = _decodeObject(response.body);
    final itemValue = decoded['item'];
    final item = itemValue is Map<String, dynamic> ? itemValue : null;
    final albumValue = item?['album'];
    final album = albumValue is Map<String, dynamic> ? albumValue : null;
    final artistsValue = item?['artists'];
    final artists = artistsValue is List<dynamic> ? artistsValue : const [];
    final artistNames = artists
        .whereType<Map<String, dynamic>>()
        .map((artist) => artist['name'])
        .whereType<String>()
        .join(', ');
    final imagesValue = album?['images'];
    final images = imagesValue is List<dynamic> ? imagesValue : const [];
    String? imageUrl;
    if (images.isNotEmpty && images.first is Map<String, dynamic>) {
      final urlValue = (images.first as Map<String, dynamic>)['url'];
      if (urlValue is String) imageUrl = urlValue;
    }
    final actionsValue = decoded['actions'];
    final actions = actionsValue is Map<String, dynamic> ? actionsValue : null;
    final disallowsValue = actions?['disallows'];
    final disallows =
        disallowsValue is Map<String, dynamic> ? disallowsValue : null;
    final externalUrlsValue = item?['external_urls'];
    final externalUrls =
        externalUrlsValue is Map<String, dynamic> ? externalUrlsValue : null;
    _setState(
      SpotifyPlayerState(
        connected: true,
        trackName: item?['name'] is String ? item!['name'] as String : null,
        artistName: artistNames.isEmpty ? null : artistNames,
        albumArtUrl: imageUrl,
        spotifyUri: item?['uri'] is String ? item!['uri'] as String : null,
        spotifyUrl: externalUrls?['spotify'] is String
            ? externalUrls!['spotify'] as String
            : null,
        isPlaying: decoded['is_playing'] == true,
        hasActiveDevice: decoded['device'] != null,
        canPause: disallows?['pausing'] != true,
        canResume: disallows?['resuming'] != true,
        canSkipNext: disallows != null && disallows['skipping_next'] != true,
        canSkipPrevious:
            disallows != null && disallows['skipping_prev'] != true,
      ),
    );
  }

  Future<void> togglePlayback() async {
    if (!_state.canTogglePlayback) {
      throw const SpotifyException(
        'Spotify does not allow play or pause for this playback right now.',
      );
    }
    final path = _state.isPlaying ? '/me/player/pause' : '/me/player/play';
    await _playerCommand('PUT', path);
    _setState(_state.copyWith(isPlaying: !_state.isPlaying));
    await _refreshSoon();
  }

  Future<void> previous() async {
    if (!_state.canSkipPrevious) {
      throw const SpotifyException(
        'Spotify does not allow skipping back for this playback.',
      );
    }
    await _playerCommand('POST', '/me/player/previous');
    await _refreshSoon();
  }

  Future<void> next() async {
    if (!_state.canSkipNext) {
      throw const SpotifyException(
        'Spotify does not allow skipping forward for this playback.',
      );
    }
    await _playerCommand('POST', '/me/player/next');
    await _refreshSoon();
  }

  Future<void> _playerCommand(String method, String path) async {
    _setState(_state.copyWith(busy: true));
    try {
      final response = await _send(method, path);
      _expectSuccess(response);
    } finally {
      _setState(_state.copyWith(busy: false));
    }
  }

  Future<void> _refreshSoon() async {
    await Future<void>.delayed(const Duration(milliseconds: 550));
    await refreshPlayback();
  }

  Future<http.Response> _send(
    String method,
    String path, {
    bool retry = true,
  }) async {
    if (!await _ensureAccessToken()) {
      throw StateError('Connect Spotify to use playback controls.');
    }
    final request = http.Request(method, Uri.parse('$_apiBase$path'))
      ..headers['Authorization'] = 'Bearer $_accessToken'
      ..headers['Content-Type'] = 'application/json';
    late http.StreamedResponse streamed;
    try {
      streamed =
          await _client.send(request).timeout(const Duration(seconds: 12));
    } on TimeoutException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        const SpotifyException(
          'Spotify took too long to respond. Check your connection and try again.',
        ),
        stackTrace,
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_asSpotifyException(error), stackTrace);
    }
    final response = await http.Response.fromStream(streamed).timeout(
      const Duration(seconds: 12),
      onTimeout: () => throw const SpotifyException(
        'Spotify took too long to respond. Check your connection and try again.',
      ),
    );
    if (response.statusCode == 401 && retry && await _refreshAccessToken()) {
      return _send(method, path, retry: false);
    }
    if (response.statusCode == 401) {
      await _clearExpiredSession();
      throw const SpotifyException(
        'Your Spotify session expired. Connect Spotify again.',
      );
    }
    return response;
  }

  Future<bool> _ensureAccessToken() async {
    final expiration = _expiration;
    if (_accessToken != null &&
        (expiration == null ||
            expiration
                .isAfter(DateTime.now().add(const Duration(minutes: 1))))) {
      return true;
    }
    return _refreshAccessToken();
  }

  Future<bool> _refreshAccessToken() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final response = await _appAuth.token(
        TokenRequest(
          clientId,
          redirectUri,
          refreshToken: refreshToken,
          serviceConfiguration: _configuration,
          scopes: _scopes,
        ),
      );
      if (response.accessToken == null) return false;
      await _saveTokens(
        accessToken: response.accessToken!,
        refreshToken: response.refreshToken ?? refreshToken,
        expiration: response.accessTokenExpirationDateTime,
      );
      return true;
    } catch (error, stackTrace) {
      debugPrint('Spotify token refresh failed: $error\n$stackTrace');
      return false;
    }
  }

  Future<void> _clearExpiredSession() async {
    _pollTimer?.cancel();
    _accessToken = null;
    _refreshToken = null;
    _expiration = null;
    try {
      await Future.wait([
        _storage.delete(key: _accessTokenKey),
        _storage.delete(key: _refreshTokenKey),
        _storage.delete(key: _expirationKey),
      ]);
    } catch (error, stackTrace) {
      debugPrint(
          'Failed to clear expired Spotify session: $error\n$stackTrace');
    }
    _setState(const SpotifyPlayerState());
  }

  Future<void> _saveTokens({
    required String accessToken,
    required String? refreshToken,
    required DateTime? expiration,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken ?? _refreshToken;
    _expiration = expiration;
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: _accessToken),
      _storage.write(key: _refreshTokenKey, value: _refreshToken),
      _storage.write(
        key: _expirationKey,
        value: _expiration?.toIso8601String(),
      ),
    ]);
  }

  void _expectSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    var message = switch (response.statusCode) {
      403 =>
        'Spotify restricted that control for this account or playback. Try play/pause or open Spotify.',
      404 => 'Open Spotify and start playing on this phone, then try again.',
      429 =>
        'Spotify is receiving too many requests. Wait a moment and try again.',
      _ => 'Spotify request failed (${response.statusCode}).',
    };
    try {
      final body = _decodeObject(response.body);
      final error = body['error'];
      if (error is Map<String, dynamic> && error['message'] is String) {
        final providerMessage = error['message'] as String;
        if (providerMessage.trim().isNotEmpty &&
            response.statusCode != 403 &&
            response.statusCode != 404) {
          message = providerMessage;
        }
      }
    } catch (_) {}
    throw SpotifyException(message);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => unawaited(_pollPlayback()),
    );
  }

  Future<void> _pollPlayback() async {
    try {
      await refreshPlayback();
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
    }
  }

  Map<String, dynamic> _decodeObject(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw const SpotifyException('Spotify returned an unreadable response.');
  }

  SpotifyException _asSpotifyException(Object error) {
    if (error is SpotifyException) return error;
    if (error is TimeoutException) {
      return const SpotifyException(
        'Spotify took too long to respond. Check your connection and try again.',
      );
    }
    return const SpotifyException(
      'Spotify could not connect. Check your connection and app settings.',
    );
  }

  String _appAuthErrorMessage(FlutterAppAuthPlatformException error) {
    final details = error.platformErrorDetails;
    final description = details.errorDescription?.trim();
    if (description != null && description.isNotEmpty) return description;
    return switch (details.error) {
      FlutterAppAuthOAuthError.invalidClient =>
        'Spotify rejected the Client ID. Check the Spotify app settings.',
      FlutterAppAuthOAuthError.invalidScope =>
        'Spotify rejected the requested playback permissions.',
      FlutterAppAuthOAuthError.unauthorizedClient =>
        'This Spotify account is not authorized to use Twistaway yet.',
      _ =>
        'Spotify login failed. Check the callback URI and Spotify app settings.',
    };
  }

  void _reportError(
    Object error,
    StackTrace stackTrace, {
    Object? debugCause,
  }) {
    final message = _asSpotifyException(error).message;
    debugPrint(
      'Spotify error: $message\nCause: ${debugCause ?? error}\n$stackTrace',
    );
    final now = DateTime.now();
    if (_lastReportedError == message &&
        _lastErrorAt != null &&
        now.difference(_lastErrorAt!) < const Duration(seconds: 45)) {
      return;
    }
    _lastReportedError = message;
    _lastErrorAt = now;
    onError?.call(message);
  }

  void _setState(SpotifyPlayerState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    onError = null;
    _pollTimer?.cancel();
    _client.close();
    super.dispose();
  }
}

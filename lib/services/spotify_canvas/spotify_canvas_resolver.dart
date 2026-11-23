import 'dart:async';
import 'dart:io';

import '../../core/utils/background_work.dart';

import '../visual_track_identity.dart';

/// Canvas is not available in Spotify's public Web API. This optional lookup
/// uses a public third-party endpoint; failure must never affect playback.
typedef CanvasJsonFetcher = Future<Map<String, dynamic>?> Function(Uri uri);
typedef CanvasMediaSizeProbe = Future<int?> Function(Uri uri);

class SpotifyCanvasTrack {
  const SpotifyCanvasTrack(this.title, this.artist, this.duration);

  final String title;
  final String artist;
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is SpotifyCanvasTrack &&
      title == other.title &&
      artist == other.artist &&
      duration == other.duration;

  @override
  int get hashCode => Object.hash(title, artist, duration);
}

class SpotifyCanvasResolver {
  SpotifyCanvasResolver({
    CanvasJsonFetcher? fetchJson,
    CanvasMediaSizeProbe? probeMediaSize,
  }) : _fetchJson = fetchJson ?? _requestJson,
       _probeMediaSize = probeMediaSize ?? _requestMediaSize;

  static const maxCanvasBytes = 10 * 1024 * 1024;

  final CanvasJsonFetcher _fetchJson;
  final CanvasMediaSizeProbe _probeMediaSize;
  final Map<SpotifyCanvasTrack, _CachedCanvas> _cache = {};
  final Map<SpotifyCanvasTrack, Future<Uri?>> _inFlight = {};
  DateTime? _cooldownUntil;

  Future<Uri?> resolve(SpotifyCanvasTrack track) {
    if (track.title.trim().isEmpty || track.artist.trim().isEmpty) {
      return Future.value(null);
    }
    final cached = _cache[track];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return Future.value(cached.url);
    }
    if (_cooldownUntil?.isAfter(DateTime.now()) == true) {
      return Future.value(null);
    }
    return _inFlight.putIfAbsent(track, () async {
      Uri? url;
      var transientFailure = false;
      try {
        url = await _resolveUncached(track);
      } on _CanvasThrottled {
        _cooldownUntil = DateTime.now().add(const Duration(seconds: 60));
        transientFailure = true;
      } catch (_) {
        // Offline, rate limited, or provider changed: retain album artwork.
        transientFailure = true;
      } finally {
        _inFlight.remove(track);
      }
      _cache[track] = _CachedCanvas(
        url,
        DateTime.now().add(
          transientFailure
              ? const Duration(seconds: 30)
              : url == null
              ? const Duration(minutes: 5)
              : const Duration(hours: 3),
        ),
      );
      if (_cache.length > 100) _cache.remove(_cache.keys.first);
      return url;
    });
  }

  Future<Uri?> _resolveUncached(SpotifyCanvasTrack track) async {
    final queryTitle = _searchTitle(track.title, track.artist);
    if (queryTitle.isEmpty) return null;
    final artist = primaryVisualArtist(track.artist);
    final fullArtist = track.artist
        .trim()
        .replaceFirst(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
        .trim();
    final ids = <String>[];
    final queries = <String>[queryTitle, '$artist - $queryTitle'];
    for (final query in queries.toSet()) {
      final search = await _fetchJson(
        Uri.https('www.spotycovs.lol', '/api/search', {'track': query}),
      );
      _checkThrottle(search);
      final results = search?['results'];
      if (results is! List) continue;
      for (final result in results) {
        if (result is! Map) continue;
        final name = result['name'];
        final artists = result['artistNames'];
        final id = result['trackId'];
        if (name is! String || artists is! List || id is! String) continue;
        if (!sameVisualTitle(queryTitle, name) || artists.isEmpty) {
          continue;
        }
        final primaryMatch =
            artists.first is String &&
            sameVisualArtist(track.artist, artists.first as String);
        final collaboratorMatch =
            !primaryMatch &&
            artists
                .skip(1)
                .any(
                  (value) =>
                      value is String && sameVisualArtist(track.artist, value),
                );
        if (!primaryMatch && !collaboratorMatch) continue;
        final durationMs = result['durationMs'];
        final visualVideo =
            cleanVisualTrackTitle(track.title) != track.title.trim();
        final tolerance = visualVideo ? 60000 : 15000;
        // A secondary credit alone is ambiguous without a matching duration.
        if (collaboratorMatch &&
            (track.duration <= Duration.zero || durationMs is! num)) {
          continue;
        }
        if (track.duration > Duration.zero &&
            durationMs is num &&
            (track.duration.inMilliseconds - durationMs).abs() > tolerance) {
          continue;
        }
        if (!_isCanvasId(id)) continue;
        if (!ids.contains(id)) ids.add(id);
        if (ids.length == 2) break;
      }
      // A verified title/artist already identifies the releases to inspect.
      // A second search here usually repeats the same IDs and costs a rate-
      // limited request even when Spotify has no Canvas for the song.
      if (ids.isNotEmpty) break;
    }
    for (final spotifyId in ids) {
      final canvas = await _fetchJson(
        Uri.https('www.spotycovs.lol', '/api/canvas', {'id': spotifyId}),
      );
      _checkThrottle(canvas);
      final url = await _videoFromCanvasPayload(
        canvas,
        expectedTrackId: spotifyId,
      );
      if (url != null) return url;
    }

    // The provider's short /api/search list can omit a popular studio track
    // entirely (for example, returning only a live "vampire" rendition).
    // Its own best-match endpoint searches the full catalog. Accept it only
    // when the returned resolution explicitly confirms title and artist.
    // Keep a band's full name ("Polo & Pan") in the query. Splitting on '&'
    // alone cannot distinguish a band from a collaboration.
    final directArtists = <String>[fullArtist];
    if (normalVisualText(fullArtist) != normalVisualText(artist) &&
        RegExp(
          r'\s+(?:feat\.?|ft\.?|featuring|x)\s+',
          caseSensitive: false,
        ).hasMatch(fullArtist)) {
      directArtists.add(artist);
    }
    for (final queryArtist in directArtists) {
      final direct = await _fetchJson(
        Uri.https('www.spotycovs.lol', '/api/canvas', {
          'track': '$queryTitle $queryArtist',
        }),
      );
      _checkThrottle(direct);
      final resolvedId = direct?['trackId'];
      // The best-match confirmation used to be nested under 'resolution'; the
      // provider now reports the same fields at the top level. Either shape is
      // accepted, but the confirmation must still name this exact recording.
      final resolution = _resolutionFields(direct);
      if (resolvedId is! String ||
          !_isCanvasId(resolvedId) ||
          resolution == null ||
          !sameVisualTitle(queryTitle, resolution.$1) ||
          normalVisualText(resolution.$2) != normalVisualText(queryArtist)) {
        continue;
      }
      final url = await _videoFromCanvasPayload(
        direct,
        expectedTrackId: resolvedId,
      );
      if (url != null) return url;
    }
    return null;
  }

  Future<Uri?> _videoFromCanvasPayload(
    Map<String, dynamic>? canvas, {
    required String expectedTrackId,
  }) async {
    final canvases = canvas?['canvases'];
    if (canvas?['hasCanvas'] != true || canvases is! List) return null;
    for (final item in canvases) {
      if (item is! Map || item['type'] != 'VIDEO') continue;
      final rawUrl = item['canvasUrl'];
      if (rawUrl is! String) continue;
      final url = Uri.tryParse(rawUrl);
      if (url != null &&
          url.scheme == 'https' &&
          url.userInfo.isEmpty &&
          url.port == 443 &&
          ((url.host == 'canvaz.scdn.co' && url.path.endsWith('.mp4')) ||
              (_isProviderStream(url) &&
                  url.queryParameters['id'] == expectedTrackId))) {
        final bytes = await _probeMediaSize(url);
        if (bytes != null && bytes > 0 && bytes <= maxCanvasBytes) {
          return url;
        }
      }
    }
    return null;
  }

  /// The provider moved from classic 22-character Spotify IDs to
  /// `t_<n>.<token>` identifiers. Both formats are accepted so a verified match
  /// is never discarded for a cosmetic reason.
  static final RegExp _canvasIdPattern = RegExp(
    r'^(?:[A-Za-z0-9]{22}|t_[0-9]+[._-][A-Za-z0-9]+)$',
  );

  static bool _isCanvasId(String id) => _canvasIdPattern.hasMatch(id);

  static bool _isProviderStream(Uri uri) =>
      (uri.host == 'www.spotycovs.lol' || uri.host == 'spotycovs.lol') &&
      uri.path == '/api/canvas' &&
      uri.queryParameters['stream'] == '1' &&
      _isCanvasId(uri.queryParameters['id'] ?? '');

  /// Best-match confirmation fields, read from the nested `resolution` block or
  /// the top level, whichever shape the provider answered with.
  static (String, String)? _resolutionFields(Map<String, dynamic>? body) {
    final nested = body?['resolution'];
    final source = nested is Map ? nested : body;
    if (source == null) return null;
    final matchedTrack = source['matchedTrack'];
    final matchedArtist = source['matchedArtist'];
    if (matchedTrack is! String || matchedArtist is! String) return null;
    return (matchedTrack, matchedArtist);
  }

  /// YouTube Music feeds hand the label as `Artist - Title`, which the provider
  /// cannot match against a recording name. The prefix is dropped only when it
  /// is exactly this track's own artist; titles that merely contain a dash keep
  /// their full identity.
  static String _searchTitle(String title, String artist) {
    final trimmed = title.trim();
    final separator = RegExp(r'^(.+?)\s+-\s+(.+)$').firstMatch(trimmed);
    if (separator == null) return cleanVisualTrackTitle(trimmed);
    final remainder = separator.group(2)!.trim();
    if (remainder.isEmpty) return cleanVisualTrackTitle(trimmed);
    final cleanedArtist = artist
        .trim()
        .replaceFirst(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
        .trim();
    final prefix = normalVisualText(cleanVisualTrackTitle(separator.group(1)!));
    if (prefix != normalVisualText(cleanedArtist) &&
        prefix != normalVisualText(primaryVisualArtist(cleanedArtist))) {
      return cleanVisualTrackTitle(trimmed);
    }
    return cleanVisualTrackTitle(remainder);
  }

  static void _checkThrottle(Map<String, dynamic>? response) {
    final code = response?['code'] ?? response?['error'];
    if (code is String &&
        (code.contains('cooldown') || code.contains('rate_limit'))) {
      throw const _CanvasThrottled();
    }
  }

  static Future<Map<String, dynamic>?> _requestJson(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode == HttpStatus.tooManyRequests) {
        throw const _CanvasThrottled();
      }
      if (response.statusCode >= HttpStatus.internalServerError) {
        throw HttpException('Canvas service temporarily unavailable');
      }
      if (response.statusCode != HttpStatus.ok ||
          response.contentLength > 256 * 1024) {
        return null;
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 5))) {
        bytes.addAll(chunk);
        if (bytes.length > 256 * 1024) {
          return null;
        }
      }
      return await parseJsonBytesInBackground(bytes, _jsonMap);
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic>? _jsonMap(Object? value) =>
      value is Map<String, dynamic> ? value : null;

  static Future<int?> _requestMediaSize(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      return await (() async {
        // Spotycovs' proxied stream is GET-only. Keep HEAD for direct Spotify
        // media, with a one-byte Range fallback when a host cannot report size.
        if (!_isProviderStream(uri)) {
          final request = await client.headUrl(uri);
          final response = await request.close();
          _checkMediaStatus(response);
          if (response.statusCode == HttpStatus.ok &&
              response.contentLength > 0) {
            return response.contentLength;
          }
          if (response.statusCode != HttpStatus.ok &&
              response.statusCode != HttpStatus.methodNotAllowed &&
              response.statusCode != HttpStatus.notImplemented) {
            return null;
          }
          await response.drain<void>();
        }

        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        final response = await request.close();
        _checkMediaStatus(response);
        final mime = response.headers.contentType?.mimeType;
        if (mime != null &&
            !mime.startsWith('video/') &&
            mime != 'application/mp4' &&
            mime != 'application/octet-stream') {
          return null;
        }
        if (response.statusCode == HttpStatus.partialContent) {
          final range = response.headers.value(HttpHeaders.contentRangeHeader);
          final total = RegExp(
            r'^bytes\s+\d+-\d+/(\d+)$',
          ).firstMatch(range ?? '')?.group(1);
          return total == null ? null : int.tryParse(total);
        }
        return response.statusCode == HttpStatus.ok &&
                response.contentLength > 0
            ? response.contentLength
            : null;
      })().timeout(const Duration(seconds: 6));
    } finally {
      client.close(force: true);
    }
  }

  static void _checkMediaStatus(HttpClientResponse response) {
    if (response.statusCode == HttpStatus.tooManyRequests) {
      throw const _CanvasThrottled();
    }
    if (response.statusCode >= HttpStatus.internalServerError &&
        response.statusCode != HttpStatus.notImplemented) {
      throw HttpException('Canvas media temporarily unavailable');
    }
  }
}

class _CanvasThrottled implements Exception {
  const _CanvasThrottled();
}

class _CachedCanvas {
  const _CachedCanvas(this.url, this.expires);

  final Uri? url;
  final DateTime expires;
}

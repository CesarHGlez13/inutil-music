import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../visual_track_identity.dart';

typedef VideoPreviewJsonFetcher =
    Future<Map<String, dynamic>?> Function(Uri uri);

/// A short official music-video preview clip used for Spotify-style Canvas
/// backgrounds (Now Playing, Artist headers, Album headers) and the vertical
/// Video Preview Clips reel.
class VideoPreviewClip {
  const VideoPreviewClip({
    required this.videoUrl,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.genre,
    this.tags = const <String>[],
    this.duration,
  });

  final Uri videoUrl;
  final String title;
  final String artist;
  final String? artworkUrl;
  final String? genre;
  final List<String> tags;
  final Duration? duration;

  @override
  bool operator ==(Object other) =>
      other is VideoPreviewClip &&
      videoUrl == other.videoUrl &&
      title == other.title &&
      artist == other.artist;

  @override
  int get hashCode => Object.hash(videoUrl, title, artist);
}

class _CachedResult<T> {
  const _CachedResult(this.value, this.expiresAt);

  final T value;
  final DateTime expiresAt;
}

/// Resolves official music-video preview clips (H.264 `.m4v`/`.mp4`) via the
/// public iTunes Search catalog (`entity=musicVideo`).
///
/// Failures, timeouts, or offline states return `null` / empty lists so audio
/// playback and page rendering are never blocked.
class VideoPreviewResolver {
  VideoPreviewResolver({
    VideoPreviewJsonFetcher? fetchJson,
    DateTime Function()? clock,
  }) : _fetchJson = fetchJson ?? _requestJson,
       _clock = clock ?? DateTime.now;

  static const _cacheTtl = Duration(minutes: 20);
  static const _missTtl = Duration(minutes: 3);
  static const _maxCacheEntries = 100;

  final VideoPreviewJsonFetcher _fetchJson;
  final DateTime Function() _clock;
  final Map<String, _CachedResult<VideoPreviewClip?>> _trackCache = {};
  final Map<String, _CachedResult<List<VideoPreviewClip>>> _clipsCache = {};
  final Map<String, Future<VideoPreviewClip?>> _trackInFlight = {};
  final Map<String, Future<List<VideoPreviewClip>>> _clipsInFlight = {};

  /// Resolves the best official music-video preview clip for a single song.
  Future<VideoPreviewClip?> resolveForTrack({
    required String title,
    required String artist,
    bool allowBroadFallback = false,
  }) {
    final cleanTitle = cleanVisualTrackTitle(title);
    final cleanArtist = primaryVisualArtist(artist);
    if (cleanTitle.isEmpty || cleanArtist.isEmpty) {
      return Future.value(null);
    }
    final key =
        '${normalVisualText(cleanArtist)}|${normalVisualText(cleanTitle)}|${allowBroadFallback ? 1 : 0}';
    final now = _clock();
    final cached = _trackCache[key];
    if (cached != null && cached.expiresAt.isAfter(now)) {
      return Future.value(cached.value);
    }
    return _trackInFlight.putIfAbsent(key, () async {
      VideoPreviewClip? resolved;
      try {
        final clips = await _searchMusicVideos(
          '$cleanArtist $cleanTitle',
          limit: 6,
        );
        // 1. Exact title + artist match.
        for (final clip in clips) {
          if (sameVisualTitle(cleanTitle, clip.title) &&
              sameVisualArtist(artist, clip.artist)) {
            resolved = clip;
            break;
          }
        }
        // 2. Same artist fallback (official video preview for artist canvas).
        resolved ??= clips.cast<VideoPreviewClip?>().firstWhere(
          (clip) => clip != null && sameVisualArtist(artist, clip.artist),
          orElse: () => null,
        );
        if (resolved == null) {
          final artistClips = await resolveClipsForArtist(artistName: artist);
          if (artistClips.isNotEmpty) {
            resolved = artistClips.first;
          }
        }
        // 3. Broad fallback for indie / YouTube-only tracks whose artist is not
        // in iTunes Music Videos: search by track title, then significant title
        // keyword so Spotify Canvas still activates smoothly.
        if (resolved == null && allowBroadFallback) {
          final titleClips = await _searchMusicVideos(cleanTitle, limit: 6);
          if (titleClips.isNotEmpty) {
            resolved = titleClips.first;
          } else {
            final words = cleanTitle
                .split(RegExp(r'[\s\-_,.;:!?()]+'))
                .map((w) => w.trim())
                .where((w) => w.length >= 5)
                .toList(growable: false);
            words.sort((a, b) => b.length.compareTo(a.length));
            for (final keyword in words.take(2)) {
              final kwClips = await _searchMusicVideos(keyword, limit: 4);
              if (kwClips.isNotEmpty) {
                resolved = kwClips.first;
                break;
              }
            }
          }
        }
      } catch (_) {
        resolved = null;
      } finally {
        _trackInFlight.remove(key);
      }
      _putCache(
        _trackCache,
        key,
        resolved,
        resolved == null ? _missTtl : _cacheTtl,
      );
      return resolved;
    });
  }

  /// Resolves a vertical reel of official music-video preview clips for an artist.
  Future<List<VideoPreviewClip>> resolveClipsForArtist({
    required String artistName,
    int maxClips = 6,
  }) {
    final cleanArtist = primaryVisualArtist(artistName);
    if (cleanArtist.isEmpty) {
      return Future.value(const <VideoPreviewClip>[]);
    }
    final key = 'artist|${normalVisualText(cleanArtist)}';
    final now = _clock();
    final cached = _clipsCache[key];
    if (cached != null && cached.expiresAt.isAfter(now)) {
      return Future.value(cached.value);
    }
    return _clipsInFlight.putIfAbsent(key, () async {
      var clips = const <VideoPreviewClip>[];
      try {
        final raw = await _searchMusicVideos(cleanArtist, limit: 12);
        final matched = <VideoPreviewClip>[];
        final seenTitles = <String>{};
        for (final clip in raw) {
          if (!sameVisualArtist(artistName, clip.artist)) continue;
          final titleKey = normalVisualText(clip.title);
          if (!seenTitles.add(titleKey)) continue;
          matched.add(clip);
          if (matched.length >= maxClips) break;
        }
        clips = List<VideoPreviewClip>.unmodifiable(matched);
      } catch (_) {
        clips = const <VideoPreviewClip>[];
      } finally {
        _clipsInFlight.remove(key);
      }
      _putCache(_clipsCache, key, clips, clips.isEmpty ? _missTtl : _cacheTtl);
      return clips;
    });
  }

  /// Resolves official music-video preview clips for an album or collection.
  Future<List<VideoPreviewClip>> resolveClipsForAlbum({
    required String albumTitle,
    required String artistName,
    int maxClips = 6,
  }) {
    final cleanAlbum = cleanVisualTrackTitle(albumTitle);
    final cleanArtist = primaryVisualArtist(artistName);
    if (cleanArtist.isEmpty && cleanAlbum.isEmpty) {
      return Future.value(const <VideoPreviewClip>[]);
    }
    final key =
        'album|${normalVisualText(cleanArtist)}|${normalVisualText(cleanAlbum)}';
    final now = _clock();
    final cached = _clipsCache[key];
    if (cached != null && cached.expiresAt.isAfter(now)) {
      return Future.value(cached.value);
    }
    return _clipsInFlight.putIfAbsent(key, () async {
      var clips = const <VideoPreviewClip>[];
      try {
        final query = cleanArtist.isEmpty
            ? cleanAlbum
            : (cleanAlbum.isEmpty ? cleanArtist : '$cleanArtist $cleanAlbum');
        final raw = await _searchMusicVideos(query, limit: 10);
        final matched = <VideoPreviewClip>[];
        final seenTitles = <String>{};
        for (final clip in raw) {
          if (cleanArtist.isNotEmpty &&
              !sameVisualArtist(artistName, clip.artist)) {
            continue;
          }
          final titleKey = normalVisualText(clip.title);
          if (!seenTitles.add(titleKey)) continue;
          matched.add(clip);
          if (matched.length >= maxClips) break;
        }
        if (matched.isEmpty && cleanArtist.isNotEmpty) {
          clips = await resolveClipsForArtist(
            artistName: artistName,
            maxClips: maxClips,
          );
        } else {
          clips = List<VideoPreviewClip>.unmodifiable(matched);
        }
      } catch (_) {
        clips = const <VideoPreviewClip>[];
      } finally {
        _clipsInFlight.remove(key);
      }
      _putCache(_clipsCache, key, clips, clips.isEmpty ? _missTtl : _cacheTtl);
      return clips;
    });
  }

  Future<List<VideoPreviewClip>> _searchMusicVideos(
    String term, {
    int limit = 8,
  }) async {
    final uri = Uri.https('itunes.apple.com', '/search', <String, String>{
      'term': term,
      'entity': 'musicVideo',
      'limit': '$limit',
    });
    final payload = await _fetchJson(uri);
    return parseItunesMusicVideoResults(payload);
  }

  void _putCache<T>(
    Map<String, _CachedResult<T>> cache,
    String key,
    T value,
    Duration ttl,
  ) {
    cache[key] = _CachedResult<T>(value, _clock().add(ttl));
    while (cache.length > _maxCacheEntries) {
      cache.remove(cache.keys.first);
    }
  }

  /// Pure parser exposed for unit testing.
  static List<VideoPreviewClip> parseItunesMusicVideoResults(
    Map<String, dynamic>? payload,
  ) {
    final results = payload?['results'];
    if (results is! List) return const <VideoPreviewClip>[];
    final clips = <VideoPreviewClip>[];
    final seenUrls = <String>{};
    for (final item in results) {
      if (item is! Map) continue;
      final rawUrl = item['previewUrl'];
      final rawTitle = item['trackName'];
      final rawArtist = item['artistName'];
      if (rawUrl is! String || rawTitle is! String || rawArtist is! String) {
        continue;
      }
      final uri = Uri.tryParse(rawUrl.trim());
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        continue;
      }
      if (!seenUrls.add(uri.toString())) continue;
      final artworkRaw = (item['artworkUrl100'] as String?)?.trim();
      final highResArtwork = artworkRaw != null && artworkRaw.isNotEmpty
          ? artworkRaw.replaceFirst('100x100bb', '600x600bb')
          : null;
      final genre = (item['primaryGenreName'] as String?)?.trim();
      final durationMs = item['trackTimeMillis'];
      final tags = buildTagsForGenre(genre);
      clips.add(
        VideoPreviewClip(
          videoUrl: uri,
          title: rawTitle.trim(),
          artist: rawArtist.trim(),
          artworkUrl: highResArtwork,
          genre: genre?.isNotEmpty == true ? genre : null,
          tags: tags,
          duration: durationMs is num && durationMs > 0
              ? Duration(milliseconds: durationMs.round())
              : null,
        ),
      );
    }
    return List<VideoPreviewClip>.unmodifiable(clips);
  }

  static List<String> buildTagsForGenre(String? genre) {
    final clean = genre?.trim();
    if (clean == null || clean.isEmpty) {
      return const <String>['#musicvideo', '#preview'];
    }
    final normalized = clean.toLowerCase();
    final primaryTag = '#${normalized.replaceAll(RegExp(r'\s+'), ' ')}';
    final extra = <String>[
      primaryTag,
      if (normalized.contains('mexican') || normalized.contains('ranchera'))
        '#regional mexicano'
      else if (normalized.contains('latin'))
        '#música latina'
      else if (normalized.contains('pop'))
        '#hits'
      else if (normalized.contains('hip-hop') || normalized.contains('rap'))
        '#urbano'
      else if (normalized.contains('rock'))
        '#live',
      '#video preview',
    ];
    return List<String>.unmodifiable(extra.toSet());
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
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 5));
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

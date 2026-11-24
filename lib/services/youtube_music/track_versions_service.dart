import 'dart:collection';

import 'innertube_models.dart';
import 'innertube_search_service.dart';

enum TrackVersionKind {
  original,
  live,
  acoustic,
  remix,
  cover,
  remaster,
  alternate;

  String label({bool spanish = true}) => switch (this) {
    TrackVersionKind.original => 'Original',
    TrackVersionKind.live => spanish ? 'En vivo' : 'Live',
    TrackVersionKind.acoustic => spanish ? 'Acústica' : 'Acoustic',
    TrackVersionKind.remix => 'Remix',
    TrackVersionKind.cover => 'Cover',
    TrackVersionKind.remaster => 'Remaster',
    TrackVersionKind.alternate => spanish ? 'Alternativa' : 'Alternate',
  };
}

class TrackVersionCandidate {
  const TrackVersionCandidate({
    required this.song,
    required this.kind,
    required this.relevanceScore,
    required this.isCurrentTrack,
  });

  final InnerTubeSong song;
  final TrackVersionKind kind;
  final double relevanceScore;
  final bool isCurrentTrack;
}

class TrackVersionLookupRequest {
  const TrackVersionLookupRequest({
    required this.title,
    required this.artist,
    this.currentVideoId,
  });

  final String title;
  final String artist;
  final String? currentVideoId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TrackVersionLookupRequest &&
            other.title == title &&
            other.artist == artist &&
            other.currentVideoId == currentVideoId;
  }

  @override
  int get hashCode => Object.hash(title, artist, currentVideoId);
}

/// Discovers and classifies alternative versions (Original, Live, Acoustic,
/// Remix, Cover, Remaster) of a song using the existing InnerTube search client.
class TrackVersionsService {
  TrackVersionsService({
    required this.search,
    this.cacheTtl = const Duration(minutes: 15),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final YouTubeMusicSearch search;
  final Duration cacheTtl;
  final DateTime Function() _clock;
  final LinkedHashMap<String, _CachedVersions> _cache =
      LinkedHashMap<String, _CachedVersions>();
  static const int _maxCacheEntries = 48;

  Future<List<TrackVersionCandidate>> findVersions(
    TrackVersionLookupRequest request,
  ) async {
    final baseTitle = stripVersionQualifiers(request.title);
    final primaryArtist = extractPrimaryArtist(request.artist);
    if (baseTitle.isEmpty) return const <TrackVersionCandidate>[];

    final cacheKey =
        '${normalizeForVersionMatch(baseTitle)}::${normalizeForVersionMatch(primaryArtist)}';
    final now = _clock();
    final cached = _cache[cacheKey];
    if (cached != null && now.isBefore(cached.expiresAt)) {
      return _markCurrent(cached.items, request.currentVideoId);
    }

    final baseQuery = primaryArtist.isEmpty
        ? baseTitle
        : '$baseTitle $primaryArtist';
    final queries = <String>[
      baseQuery,
      '$baseQuery live acoustic',
      '$baseQuery remix cover',
    ];

    final settled = await Future.wait<List<InnerTubeSong>>(
      queries.map((query) async {
        try {
          return await search.searchSongs(query, limit: 12);
        } catch (_) {
          return const <InnerTubeSong>[];
        }
      }),
    );

    final deduped = <String, InnerTubeSong>{};
    for (final batch in settled) {
      for (final song in batch) {
        final id = song.videoId.trim();
        if (id.isEmpty) continue;
        deduped.putIfAbsent(id, () => song);
      }
    }

    final classified = classifyCandidates(
      baseTitle: baseTitle,
      primaryArtist: primaryArtist,
      candidates: deduped.values,
      currentVideoId: request.currentVideoId,
    );

    _cache[cacheKey] = _CachedVersions(
      items: classified,
      expiresAt: now.add(cacheTtl),
    );
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    return classified;
  }

  List<TrackVersionCandidate> _markCurrent(
    List<TrackVersionCandidate> items,
    String? currentVideoId,
  ) {
    final current = currentVideoId?.trim();
    if (current == null || current.isEmpty) return items;
    return items
        .map(
          (item) => TrackVersionCandidate(
            song: item.song,
            kind: item.kind,
            relevanceScore: item.relevanceScore,
            isCurrentTrack: item.song.videoId == current,
          ),
        )
        .toList(growable: false);
  }

  /// Pure classification & relevance filtering exposed for deterministic unit tests.
  static List<TrackVersionCandidate> classifyCandidates({
    required String baseTitle,
    required String primaryArtist,
    required Iterable<InnerTubeSong> candidates,
    String? currentVideoId,
  }) {
    final cleanBaseTitle = stripVersionQualifiers(baseTitle);
    final baseTokens = _meaningfulTokens(cleanBaseTitle);
    if (baseTokens.isEmpty) return const <TrackVersionCandidate>[];
    final artistTokens = _meaningfulTokens(primaryArtist);
    final normalizedCurrentId = currentVideoId?.trim();

    final results = <TrackVersionCandidate>[];
    for (final song in candidates) {
      final candidateBaseTitle = stripVersionQualifiers(song.title);
      final candidateTitleTokens = _meaningfulTokens(candidateBaseTitle);
      if (candidateTitleTokens.isEmpty) continue;

      final matchedTitleTokens = baseTokens
          .where(candidateTitleTokens.contains)
          .length;
      final titleRecall = matchedTitleTokens / baseTokens.length;
      final titlePrecision = matchedTitleTokens / candidateTitleTokens.length;

      // Guardrail: reject unrelated songs that don't carry the song's title.
      if (titleRecall < 0.65 || (baseTokens.length >= 2 && titlePrecision < 0.45)) {
        continue;
      }

      final candidateArtistsText = song.artists.join(' ');
      final candidateArtistTokens = _meaningfulTokens(candidateArtistsText);
      final artistMatched = artistTokens.isEmpty
          ? true
          : artistTokens.any(candidateArtistTokens.contains);

      final kind = detectVersionKind(
        title: song.title,
        album: song.album,
        candidateArtists: song.artists,
        expectedPrimaryArtist: primaryArtist,
        artistMatched: artistMatched,
      );

      // Non-cover / non-remix versions must match the artist when one is known.
      if (!artistMatched &&
          kind != TrackVersionKind.cover &&
          kind != TrackVersionKind.remix) {
        continue;
      }

      var score = (titleRecall * 0.6) + (titlePrecision * 0.25);
      if (artistMatched) score += 0.25;
      if (kind == TrackVersionKind.original && artistMatched) score += 0.08;
      if (song.videoId == normalizedCurrentId) score += 0.05;

      results.add(
        TrackVersionCandidate(
          song: song,
          kind: kind,
          relevanceScore: score,
          isCurrentTrack:
              normalizedCurrentId != null &&
              normalizedCurrentId.isNotEmpty &&
              song.videoId == normalizedCurrentId,
        ),
      );
    }

    // Order by category diversity & relevance so Original -> Live -> Acoustic ->
    // Remix -> Cover -> Remaster surface cleanly.
    const kindPriority = <TrackVersionKind, int>{
      TrackVersionKind.original: 0,
      TrackVersionKind.live: 1,
      TrackVersionKind.acoustic: 2,
      TrackVersionKind.remix: 3,
      TrackVersionKind.remaster: 4,
      TrackVersionKind.cover: 5,
      TrackVersionKind.alternate: 6,
    };

    results.sort((a, b) {
      if (a.isCurrentTrack != b.isCurrentTrack) {
        return a.isCurrentTrack ? 1 : -1;
      }
      final kindCmp = (kindPriority[a.kind] ?? 9).compareTo(
        kindPriority[b.kind] ?? 9,
      );
      if (kindCmp != 0) return kindCmp;
      final scoreCmp = b.relevanceScore.compareTo(a.relevanceScore);
      if (scoreCmp != 0) return scoreCmp;
      return a.song.videoId.compareTo(b.song.videoId);
    });

    return List<TrackVersionCandidate>.unmodifiable(results);
  }

  static TrackVersionKind detectVersionKind({
    required String title,
    String? album,
    List<String> candidateArtists = const <String>[],
    String expectedPrimaryArtist = '',
    bool artistMatched = true,
  }) {
    final text = '$title ${album ?? ''}'.toLowerCase();
    if (_livePattern.hasMatch(text)) return TrackVersionKind.live;
    if (_acousticPattern.hasMatch(text)) return TrackVersionKind.acoustic;
    if (_remixPattern.hasMatch(text)) return TrackVersionKind.remix;
    if (_remasterPattern.hasMatch(text)) return TrackVersionKind.remaster;
    if (_coverPattern.hasMatch(text)) return TrackVersionKind.cover;
    if (_alternatePattern.hasMatch(text)) return TrackVersionKind.alternate;
    if (!artistMatched && expectedPrimaryArtist.trim().isNotEmpty) {
      return TrackVersionKind.cover;
    }
    return TrackVersionKind.original;
  }

  static String stripVersionQualifiers(String rawTitle) {
    var cleaned = rawTitle.trim();
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ');
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s*[-–—|]\s*(live|en vivo|ac[uú]stic[ao]?|acoustic|unplugged|remix|remaster(ed)?|cover|karaoke|instrumental|sped up|slowed|reverb|radio edit|version|versi[oó]n).*$',
        caseSensitive: false,
      ),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'\b(feat\.?|ft\.?|con)\s+.*$', caseSensitive: false),
      '',
    );
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String extractPrimaryArtist(String rawArtist) {
    final first = rawArtist
        .split(RegExp(r',|&| x | feat\.?| ft\.?|/|•|·', caseSensitive: false))
        .first
        .trim();
    if (first.toLowerCase() == 'inútil music' ||
        first.toLowerCase() == 'unknown artist' ||
        first.toLowerCase() == 'artista desconocido') {
      return '';
    }
    return first;
  }

  static String normalizeForVersionMatch(String input) {
    var text = input.toLowerCase().trim();
    text = text
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
    text = text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static Set<String> _meaningfulTokens(String input) {
    final normalized = normalizeForVersionMatch(input);
    if (normalized.isEmpty) return const <String>{};
    final parts = normalized.split(' ').where((t) => t.isNotEmpty).toList();
    final filtered = parts
        .where((t) => t.length > 1 || parts.length == 1)
        .toSet();
    return filtered.isEmpty ? parts.toSet() : filtered;
  }

  static final RegExp _livePattern = RegExp(
    r'\b(live|en vivo|en directo|concierto|concert|session|sesi[oó]n|tiny desk|mtv|festival|tour)\b',
    caseSensitive: false,
  );
  static final RegExp _acousticPattern = RegExp(
    r'\b(acoustic|ac[uú]stic[ao]?|unplugged|piano version|guitar version|stripped)\b',
    caseSensitive: false,
  );
  static final RegExp _remixPattern = RegExp(
    r'\b(remix|rework|bootleg|club mix|dj mix|extended mix|mashup|edit|dub)\b',
    caseSensitive: false,
  );
  static final RegExp _remasterPattern = RegExp(
    r'\b(remaster(ed)?|deluxe|anniversary|re-recorded|taylor.?s version)\b',
    caseSensitive: false,
  );
  static final RegExp _coverPattern = RegExp(
    r'\b(cover|tribute|tributo|version by|versi[oó]n de)\b',
    caseSensitive: false,
  );
  static final RegExp _alternatePattern = RegExp(
    r'\b(sped up|slowed|reverb|nightcore|8d|instrumental|karaoke|demo|radio edit)\b',
    caseSensitive: false,
  );
}

class _CachedVersions {
  const _CachedVersions({required this.items, required this.expiresAt});

  final List<TrackVersionCandidate> items;
  final DateTime expiresAt;
}

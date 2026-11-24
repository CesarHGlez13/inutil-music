import 'package:flutter/foundation.dart';

import '../../features/music/domain/entities/track_info.dart';
import 'recommendation_storage_models.dart';

@immutable
class TimeMachineTrack {
  const TimeMachineTrack({
    required this.trackKey,
    required this.trackId,
    this.videoId,
    required this.title,
    required this.artist,
    this.album,
    this.thumbnailUrl,
    this.durationMs,
    required this.playCount,
    required this.totalListenedMs,
    required this.lastPlayedAt,
    required this.firstPlayedAt,
    this.isFavorite = false,
  });

  final String trackKey;
  final String trackId;
  final String? videoId;
  final String title;
  final String artist;
  final String? album;
  final String? thumbnailUrl;
  final int? durationMs;
  final int playCount;
  final int totalListenedMs;
  final DateTime lastPlayedAt;
  final DateTime firstPlayedAt;
  final bool isFavorite;

  int get totalMinutes => (totalListenedMs / 60000).round();

  int daysSinceLastPlayed(DateTime now) =>
      now.toUtc().difference(lastPlayedAt.toUtc()).inDays.clamp(0, 99999);

  TrackInfo toTrackInfo() {
    final resolvedId = (videoId != null && videoId!.trim().isNotEmpty)
        ? videoId!.trim()
        : trackId;
    final url = (videoId != null && videoId!.trim().isNotEmpty)
        ? 'https://music.youtube.com/watch?v=${videoId!.trim()}'
        : '';
    return TrackInfo(
      id: resolvedId,
      title: title,
      artist: artist,
      album: album,
      thumbnailUrl: thumbnailUrl,
      url: url,
      duration: durationMs != null && durationMs! > 0
          ? Duration(milliseconds: durationMs!)
          : null,
    );
  }
}

@immutable
class TimeMachineMonthCapsule {
  const TimeMachineMonthCapsule({
    required this.year,
    required this.month,
    required this.totalPlays,
    required this.totalListenedMs,
    required this.uniqueTracks,
    required this.topArtist,
    required this.tracks,
  });

  final int year;
  final int month;
  final int totalPlays;
  final int totalListenedMs;
  final int uniqueTracks;
  final String topArtist;
  final List<TimeMachineTrack> tracks;

  String get monthKey => '$year-${month.toString().padLeft(2, '0')}';

  int get totalMinutes => (totalListenedMs / 60000).round();

  String label({bool spanish = true}) {
    const monthsEs = <String>[
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    const monthsEn = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final name = (spanish ? monthsEs : monthsEn)[(month - 1).clamp(0, 11)];
    return '$name $year';
  }
}

@immutable
class TimeMachineSnapshot {
  const TimeMachineSnapshot({
    required this.onThisDateTitle,
    required this.onThisDateSubtitle,
    required this.onThisDateTracks,
    required this.forgottenFavorites,
    required this.monthlyCapsules,
    required this.totalTrackedPlays,
    required this.totalTrackedMinutes,
  });

  final String onThisDateTitle;
  final String onThisDateSubtitle;
  final List<TimeMachineTrack> onThisDateTracks;
  final List<TimeMachineTrack> forgottenFavorites;
  final List<TimeMachineMonthCapsule> monthlyCapsules;
  final int totalTrackedPlays;
  final int totalTrackedMinutes;

  bool get isEmpty =>
      totalTrackedPlays == 0 &&
      monthlyCapsules.isEmpty &&
      forgottenFavorites.isEmpty &&
      onThisDateTracks.isEmpty;
}

/// Pure analyzer that transforms playback history into Máquina del Tiempo
/// capsules ("Hace un año", "Canciones que amabas y olvidaste", and month-by-month).
class TimeMachineAnalyzer {
  const TimeMachineAnalyzer._();

  static TimeMachineSnapshot analyze(
    List<PlaybackEvent> events, {
    DateTime? now,
    bool spanish = true,
    Duration forgottenMinAge = const Duration(days: 21),
    int forgottenMinPlays = 2,
  }) {
    final reference = (now ?? DateTime.now()).toUtc();
    if (events.isEmpty) {
      return TimeMachineSnapshot(
        onThisDateTitle: spanish ? 'Hace un año' : 'One year ago',
        onThisDateSubtitle: spanish
            ? 'Escucha música en Inutix Music para empezar a construir tu cápsula temporal.'
            : 'Listen to music in Inutix Music to start building your time capsule.',
        onThisDateTracks: const <TimeMachineTrack>[],
        forgottenFavorites: const <TimeMachineTrack>[],
        monthlyCapsules: const <TimeMachineMonthCapsule>[],
        totalTrackedPlays: 0,
        totalTrackedMinutes: 0,
      );
    }

    final globalByTrack = <String, _TrackAccumulator>{};
    final eventsByMonth = <String, List<PlaybackEvent>>{};
    var totalListenedMs = 0;

    for (final event in events) {
      totalListenedMs += event.listenedMs;
      final acc = globalByTrack.putIfAbsent(
        event.trackKey,
        () => _TrackAccumulator.fromEvent(event),
      );
      acc.add(event);

      final localPlayed = event.playedAt.toLocal();
      final key =
          '${localPlayed.year}-${localPlayed.month.toString().padLeft(2, '0')}';
      eventsByMonth.putIfAbsent(key, () => <PlaybackEvent>[]).add(event);
    }

    // 1. Forgotten favorites ("Canciones que amabas y olvidaste")
    final forgottenCutoff = reference.subtract(forgottenMinAge);
    final forgotten = globalByTrack.values
        .where(
          (acc) =>
              (acc.playCount >= forgottenMinPlays || acc.isFavorite) &&
              acc.lastPlayedAt.toUtc().isBefore(forgottenCutoff),
        )
        .map((acc) => acc.build())
        .toList(growable: false)
      ..sort((a, b) {
        final scoreA =
            (a.playCount * (a.isFavorite ? 1.5 : 1.0)) *
            (1 + (a.daysSinceLastPlayed(reference) / 60.0));
        final scoreB =
            (b.playCount * (b.isFavorite ? 1.5 : 1.0)) *
            (1 + (b.daysSinceLastPlayed(reference) / 60.0));
        final cmp = scoreB.compareTo(scoreA);
        if (cmp != 0) return cmp;
        return a.trackKey.compareTo(b.trackKey);
      });

    // 2. Monthly capsules sorted newest -> oldest
    final sortedMonthKeys = eventsByMonth.keys.toList(growable: false)
      ..sort((a, b) => b.compareTo(a));
    final monthlyCapsules = <TimeMachineMonthCapsule>[];
    for (final key in sortedMonthKeys) {
      final monthEvents = eventsByMonth[key]!;
      final parts = key.split('-');
      final year = int.tryParse(parts[0]) ?? reference.year;
      final month = int.tryParse(parts[1]) ?? reference.month;

      final monthAcc = <String, _TrackAccumulator>{};
      final artistPlays = <String, int>{};
      var monthMs = 0;

      for (final event in monthEvents) {
        monthMs += event.listenedMs;
        final acc = monthAcc.putIfAbsent(
          event.trackKey,
          () => _TrackAccumulator.fromEvent(event),
        );
        acc.add(event);
        final artist = event.artists.isNotEmpty
            ? event.artists.first.trim()
            : '';
        if (artist.isNotEmpty) {
          artistPlays[artist] = (artistPlays[artist] ?? 0) + 1;
        }
      }

      var topArtist = spanish ? 'Varios artistas' : 'Various artists';
      var topArtistCount = 0;
      artistPlays.forEach((artist, count) {
        if (count > topArtistCount) {
          topArtistCount = count;
          topArtist = artist;
        }
      });

      final monthTracks = monthAcc.values
          .map((acc) => acc.build())
          .toList(growable: false)
        ..sort((a, b) {
          final playCmp = b.playCount.compareTo(a.playCount);
          if (playCmp != 0) return playCmp;
          final listenCmp = b.totalListenedMs.compareTo(a.totalListenedMs);
          if (listenCmp != 0) return listenCmp;
          return b.lastPlayedAt.compareTo(a.lastPlayedAt);
        });

      monthlyCapsules.add(
        TimeMachineMonthCapsule(
          year: year,
          month: month,
          totalPlays: monthEvents.length,
          totalListenedMs: monthMs,
          uniqueTracks: monthAcc.length,
          topArtist: topArtist,
          tracks: List<TimeMachineTrack>.unmodifiable(monthTracks.take(30)),
        ),
      );
    }

    // 3. "Hace un año / En esta época" (prior years near same month, or earliest
    // recorded month when the account's history is less than 11 months old).
    final localRef = reference.toLocal();
    final priorYearEvents = events.where((event) {
      final played = event.playedAt.toLocal();
      if (played.year >= localRef.year) return false;
      final monthDiff = (played.month - localRef.month).abs();
      return monthDiff <= 1 || monthDiff == 11;
    }).toList(growable: false);

    String onThisDateTitle;
    String onThisDateSubtitle;
    List<TimeMachineTrack> onThisDateTracks;

    if (priorYearEvents.isNotEmpty) {
      final accMap = <String, _TrackAccumulator>{};
      for (final event in priorYearEvents) {
        accMap
            .putIfAbsent(
              event.trackKey,
              () => _TrackAccumulator.fromEvent(event),
            )
            .add(event);
      }
      onThisDateTracks = accMap.values
          .map((acc) => acc.build())
          .toList(growable: false)
        ..sort((a, b) => b.playCount.compareTo(a.playCount));
      onThisDateTitle = spanish
          ? 'Lo que escuchabas hace un año'
          : 'What you played a year ago';
      onThisDateSubtitle = spanish
          ? 'Tus canciones favoritas alrededor de estas fechas en años anteriores.'
          : 'Your favorite tracks around this time in previous years.';
    } else if (monthlyCapsules.length >= 2) {
      final earliest = monthlyCapsules.last;
      onThisDateTracks = earliest.tracks;
      onThisDateTitle = spanish
          ? 'Tu primer recuerdo · ${earliest.label(spanish: true)}'
          : 'Your earliest capsule · ${earliest.label(spanish: false)}';
      onThisDateSubtitle = spanish
          ? 'Así sonaban tus primeros días registrados en Inutix Music.'
          : 'Here is how your earliest recorded days sounded in Inutix Music.';
    } else {
      final only = monthlyCapsules.first;
      onThisDateTracks = only.tracks;
      onThisDateTitle = spanish
          ? 'Cápsula actual · ${only.label(spanish: true)}'
          : 'Current capsule · ${only.label(spanish: false)}';
      onThisDateSubtitle = spanish
          ? 'A medida que pasen los meses aquí aparecerán tus recuerdos de hace un año.'
          : 'As months go by, your memories from a year ago will appear here.';
    }

    return TimeMachineSnapshot(
      onThisDateTitle: onThisDateTitle,
      onThisDateSubtitle: onThisDateSubtitle,
      onThisDateTracks: List<TimeMachineTrack>.unmodifiable(
        onThisDateTracks.take(25),
      ),
      forgottenFavorites: List<TimeMachineTrack>.unmodifiable(
        forgotten.take(30),
      ),
      monthlyCapsules: List<TimeMachineMonthCapsule>.unmodifiable(
        monthlyCapsules,
      ),
      totalTrackedPlays: events.length,
      totalTrackedMinutes: (totalListenedMs / 60000).round(),
    );
  }
}

class _TrackAccumulator {
  _TrackAccumulator.fromEvent(PlaybackEvent event)
    : trackKey = event.trackKey,
      trackId = event.trackId,
      videoId = event.videoId,
      title = event.title,
      artist = event.artists.isNotEmpty
          ? event.artists.join(', ')
          : 'Inutix Music',
      album = event.album,
      thumbnailUrl = event.thumbnailUrl,
      durationMs = event.durationMs,
      lastPlayedAt = event.playedAt,
      firstPlayedAt = event.playedAt,
      isFavorite = event.isFavorite == true || event.isLiked == true;

  final String trackKey;
  String trackId;
  String? videoId;
  String title;
  String artist;
  String? album;
  String? thumbnailUrl;
  int? durationMs;
  int playCount = 0;
  int totalListenedMs = 0;
  DateTime lastPlayedAt;
  DateTime firstPlayedAt;
  bool isFavorite;

  void add(PlaybackEvent event) {
    playCount += 1;
    totalListenedMs += event.listenedMs;
    if (event.playedAt.isAfter(lastPlayedAt)) {
      lastPlayedAt = event.playedAt;
      if (event.title.trim().isNotEmpty) title = event.title;
      if (event.artists.isNotEmpty) artist = event.artists.join(', ');
      if (event.thumbnailUrl?.trim().isNotEmpty == true) {
        thumbnailUrl = event.thumbnailUrl;
      }
      if (event.videoId?.trim().isNotEmpty == true) {
        videoId = event.videoId;
      }
    }
    if (event.playedAt.isBefore(firstPlayedAt)) {
      firstPlayedAt = event.playedAt;
    }
    if (event.isFavorite == true || event.isLiked == true) {
      isFavorite = true;
    }
  }

  TimeMachineTrack build() => TimeMachineTrack(
    trackKey: trackKey,
    trackId: trackId,
    videoId: videoId,
    title: title,
    artist: artist,
    album: album,
    thumbnailUrl: thumbnailUrl,
    durationMs: durationMs,
    playCount: playCount,
    totalListenedMs: totalListenedMs,
    lastPlayedAt: lastPlayedAt,
    firstPlayedAt: firstPlayedAt,
    isFavorite: isFavorite,
  );
}

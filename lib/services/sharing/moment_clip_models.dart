import 'package:flutter/foundation.dart';

import '../../features/music/domain/entities/lyrics.dart';

enum MomentClipMode {
  lyrics,
  player;

  String get wireValue => switch (this) {
    MomentClipMode.lyrics => 'lyrics',
    MomentClipMode.player => 'player',
  };
}

enum MomentExportStage {
  preparing,
  audio,
  video,
  done;

  static MomentExportStage parse(String? raw) => switch (raw?.trim()) {
    'audio' => MomentExportStage.audio,
    'video' => MomentExportStage.video,
    'done' => MomentExportStage.done,
    _ => MomentExportStage.preparing,
  };
}

@immutable
class MomentExportableAudioSource {
  const MomentExportableAudioSource({
    required this.uri,
    this.httpHeaders = const <String, String>{},
  });

  final String uri;
  final Map<String, String> httpHeaders;

  bool get isValid => uri.trim().isNotEmpty;
}

@immutable
class MomentClipCapabilities {
  const MomentClipCapabilities({
    required this.width,
    required this.height,
    required this.fps,
  });

  final int width;
  final int height;
  final int fps;

  String get badgeLabel => '${height >= 1920 ? '1080p' : '720p'} · ${fps}fps';
}

@immutable
class MomentClipProgress {
  const MomentClipProgress({
    required this.jobId,
    required this.stage,
    required this.progress,
  });

  final String jobId;
  final MomentExportStage stage;
  final double progress;
}

@immutable
class MomentClipExportResult {
  const MomentClipExportResult({
    required this.outputPath,
    required this.width,
    required this.height,
    required this.fps,
    required this.sizeBytes,
    required this.duration,
  });

  final String outputPath;
  final int width;
  final int height;
  final int fps;
  final int sizeBytes;
  final Duration duration;
}

/// Pure, clamped clip time window (`[start, end]`) inside a track timeline.
@immutable
class MomentClipWindow {
  const MomentClipWindow({
    required this.start,
    required this.duration,
    required this.trackDuration,
  });

  static const minDuration = Duration(seconds: 5);
  static const maxDuration = Duration(seconds: 30);
  static const defaultDuration = Duration(seconds: 15);
  static const durationPresets = <Duration>[
    Duration(seconds: 10),
    Duration(seconds: 15),
    Duration(seconds: 20),
    Duration(seconds: 30),
  ];

  final Duration start;
  final Duration duration;
  final Duration trackDuration;

  Duration get end => start + duration;

  /// Resolves a valid window clamped to `[0, trackDuration]` with duration in
  /// `[5s, 30s]` (or full track if the track itself is shorter than 5s).
  factory MomentClipWindow.resolve({
    required Duration requestedStart,
    required Duration requestedDuration,
    required Duration trackDuration,
  }) {
    final safeTrack = trackDuration > Duration.zero
        ? trackDuration
        : defaultDuration;
    final effectiveMin = safeTrack < minDuration ? safeTrack : minDuration;
    final effectiveMax = safeTrack < maxDuration ? safeTrack : maxDuration;
    final clampedDuration = _clampDuration(
      requestedDuration,
      effectiveMin,
      effectiveMax,
    );
    final maxStart = safeTrack - clampedDuration;
    final clampedStart = _clampDuration(
      requestedStart,
      Duration.zero,
      maxStart < Duration.zero ? Duration.zero : maxStart,
    );
    return MomentClipWindow(
      start: clampedStart,
      duration: clampedDuration,
      trackDuration: safeTrack,
    );
  }

  MomentClipWindow withStart(Duration newStart) => MomentClipWindow.resolve(
    requestedStart: newStart,
    requestedDuration: duration,
    trackDuration: trackDuration,
  );

  MomentClipWindow withDuration(Duration newDuration) => MomentClipWindow.resolve(
    requestedStart: start,
    requestedDuration: newDuration,
    trackDuration: trackDuration,
  );

  static Duration _clampDuration(Duration value, Duration min, Duration max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MomentClipWindow &&
          start == other.start &&
          duration == other.duration &&
          trackDuration == other.trackDuration;

  @override
  int get hashCode => Object.hash(start, duration, trackDuration);
}

@immutable
class MomentClipExportRequest {
  const MomentClipExportRequest({
    required this.jobId,
    required this.mode,
    required this.title,
    required this.artist,
    required this.audioSource,
    required this.start,
    required this.end,
    required this.trackDuration,
    required this.accentColorArgb,
    this.album,
    this.videoUri,
    this.videoStartOffset = Duration.zero,
    this.artworkSource,
    this.lyricsOffset = Duration.zero,
    this.lyricsCentered = false,
    this.lyricsProviderLabel,
    this.lyrics = const <LyricLine>[],
  });

  final String jobId;
  final MomentClipMode mode;
  final String title;
  final String artist;
  final String? album;
  final MomentExportableAudioSource audioSource;
  final Uri? videoUri;
  final Duration videoStartOffset;
  final String? artworkSource;
  final int accentColorArgb;
  final Duration start;
  final Duration end;
  final Duration trackDuration;
  final Duration lyricsOffset;
  final bool lyricsCentered;
  final String? lyricsProviderLabel;
  final List<LyricLine> lyrics;

  Map<String, Object?> toChannelMap({required String outputPath}) {
    return <String, Object?>{
      'jobId': jobId,
      'mode': mode.wireValue,
      'title': title,
      'artist': artist,
      'album': album,
      'audioUri': audioSource.uri,
      'audioHeaders': audioSource.httpHeaders,
      'videoUri': videoUri?.toString(),
      'videoStartOffsetMs': videoStartOffset.inMilliseconds,
      'artworkSource': artworkSource,
      'accentColorArgb': accentColorArgb,
      'startMs': start.inMilliseconds,
      'endMs': end.inMilliseconds,
      'trackDurationMs': trackDuration.inMilliseconds,
      'lyricsOffsetMs': lyricsOffset.inMilliseconds,
      'lyricsCentered': lyricsCentered,
      'lyricsProviderLabel': lyricsProviderLabel,
      'lyrics': lyrics
          .where((line) => line.text.trim().isNotEmpty)
          .map(
            (line) => <String, Object?>{
              'timestampMs': line.timestamp.inMilliseconds,
              'text': line.text,
              'words': line.hasWordTiming
                  ? line.words
                        .map(
                          (word) => <String, Object?>{
                            'text': word.text,
                            'startMs': word.start.inMilliseconds,
                            'endMs': word.end.inMilliseconds,
                            'startOffset': word.startOffset,
                            'endOffset': word.endOffset,
                          },
                        )
                        .toList(growable: false)
                  : const <Map<String, Object?>>[],
            },
          )
          .toList(growable: false),
      'outputPath': outputPath,
    };
  }
}

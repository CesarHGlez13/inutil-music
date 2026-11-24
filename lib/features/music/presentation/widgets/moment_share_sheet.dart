import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/duration_formatter.dart';
import '../../../../services/player/player_service.dart';
import '../../../../services/sharing/moment_clip_export_service.dart';
import '../../../../services/sharing/moment_clip_models.dart';
import '../../domain/entities/lyrics.dart';
import '../../domain/entities/track_info.dart';
import '../providers/app_strings.dart';
import '../providers/moment_clip_providers.dart';
import '../providers/music_providers.dart';
import '../providers/playback_artwork_provider.dart';
import '../providers/playback_visual_cache_provider.dart';
import 'source_image.dart';
import 'spotify_canvas_video.dart';

/// Opens the fullscreen "Compartir momento" clip studio modal where the user
/// chooses the moment window (5–30s), previews Lyrics or Player visual style
/// with the translucent Inútil Music watermark, and exports a high-quality MP4
/// ready for WhatsApp HD, Instagram, and TikTok without screen recording.
Future<void> showMomentShareSheet({
  required BuildContext context,
  required MomentClipMode initialMode,
  Uri? videoUri,
  Duration videoStartOffset = Duration.zero,
  String? artworkSource,
  String? artworkFallbackSource,
  Color? accentColor,
}) async {
  await Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => MomentShareSheet(
        initialMode: initialMode,
        videoUri: videoUri,
        videoStartOffset: videoStartOffset,
        artworkSource: artworkSource,
        artworkFallbackSource: artworkFallbackSource,
        accentColor: accentColor,
      ),
    ),
  );
}

class MomentShareSheet extends ConsumerStatefulWidget {
  const MomentShareSheet({
    required this.initialMode,
    this.videoUri,
    this.videoStartOffset = Duration.zero,
    this.artworkSource,
    this.artworkFallbackSource,
    this.accentColor,
    super.key,
  });

  final MomentClipMode initialMode;
  final Uri? videoUri;
  final Duration videoStartOffset;
  final String? artworkSource;
  final String? artworkFallbackSource;
  final Color? accentColor;

  @override
  ConsumerState<MomentShareSheet> createState() => _MomentShareSheetState();
}

class _MomentShareSheetState extends ConsumerState<MomentShareSheet> {
  final _shareButtonKey = GlobalKey();

  late MomentClipMode _mode;
  late MomentClipWindow _window;
  MomentClipCapabilities _capabilities = const MomentClipCapabilities(
    width: 1080,
    height: 1920,
    fps: 60,
  );

  bool _auditioning = false;
  Timer? _auditionTimer;
  Duration _previewPlayheadOffset = Duration.zero;
  bool _wasPlayingBeforeAudition = false;

  bool _exporting = false;
  String? _activeJobId;
  MomentExportStage _exportStage = MomentExportStage.preparing;
  double _exportProgress = 0.0;
  String? _errorMessage;

  bool _userAdjustedWindow = false;

  // Frozen snapshot captured when the sheet opens so background auto-advance
  // never swaps the song or lyrics while the user is trimming/exporting.
  PlayerSnapshot? _frozenSnapshot;
  LyricsDocument? _frozenLyrics;
  Duration _frozenLyricsOffset = Duration.zero;
  String? _frozenArtworkSource;
  String? _frozenArtworkFallback;
  Color? _frozenAccentColor;

  // Reuse an already-rendered clip if user shares and then taps Save without
  // changing the mode or selected moment window.
  String? _cachedSignature;
  MomentClipExportResult? _cachedResult;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    final initialSnapshot = ref.read(playerControllerProvider).value;
    _captureFrozenContext(initialSnapshot);
    final snapshot =
        _frozenSnapshot ?? const PlayerSnapshot(status: PlayerStatus.idle);
    final trackDuration = _resolveTrackDuration(snapshot);
    final initialStart = _initialWindowStart(snapshot.position, trackDuration);
    _window = MomentClipWindow.resolve(
      requestedStart: initialStart,
      requestedDuration: MomentClipWindow.defaultDuration,
      trackDuration: trackDuration,
    );
    if (initialSnapshot == null) {
      ref.listenManual<AsyncValue<PlayerSnapshot>>(
        playerControllerProvider,
        (_, next) {
          final resolved = next.value;
          if (!mounted || _frozenSnapshot != null || resolved == null) return;
          _captureFrozenContext(resolved);
          if (_userAdjustedWindow) return;
          final dur = _resolveTrackDuration(resolved);
          final start = _initialWindowStart(resolved.position, dur);
          setState(() {
            _window = MomentClipWindow.resolve(
              requestedStart: start,
              requestedDuration: _window.duration,
              trackDuration: dur,
            );
          });
        },
      );
    }
    unawaited(_loadCapabilities());
  }

  void _captureFrozenContext(PlayerSnapshot? snapshot) {
    if (snapshot == null) return;
    _frozenSnapshot = snapshot;
    _frozenLyrics = ref.read(currentLyricsDocumentProvider);
    _frozenLyricsOffset = ref.read(lyricsOffsetControllerProvider);
    final artwork = ref.read(playbackArtworkProvider);
    _frozenArtworkSource = widget.artworkSource ?? artwork.source ?? snapshot.thumbnailUrl;
    _frozenArtworkFallback = widget.artworkFallbackSource ?? artwork.fallback;
    _frozenAccentColor = widget.accentColor ?? ref.read(playbackArtworkColorProvider);
  }

  @override
  void dispose() {
    _stopAudition(restorePlayback: false);
    if (_exporting) {
      unawaited(
        ref
            .read(momentClipExportServiceProvider)
            .cancelExport(jobId: _activeJobId),
      );
    }
    super.dispose();
  }

  Future<void> _loadCapabilities() async {
    final caps = await ref
        .read(momentClipExportServiceProvider)
        .probeCapabilities();
    if (!mounted || caps == null) return;
    setState(() => _capabilities = caps);
  }

  Duration _resolveTrackDuration(PlayerSnapshot snapshot) {
    final d = snapshot.duration;
    if (d != null && d > Duration.zero) return d;
    final lyrics = ref.read(currentLyricsDocumentProvider);
    if (lyrics != null && lyrics.lines.isNotEmpty) {
      return lyrics.lines.last.timestamp + const Duration(seconds: 12);
    }
    return const Duration(minutes: 3);
  }

  Duration _initialWindowStart(Duration currentPosition, Duration trackDuration) {
    // Anchor slightly before current position if lyrics exist so the active
    // phrase starts naturally instead of mid-word.
    final lyrics = ref.read(currentLyricsDocumentProvider);
    if (lyrics != null && lyrics.lines.isNotEmpty) {
      LyricLine? matched;
      for (final line in lyrics.lines) {
        if (line.timestamp <= currentPosition + const Duration(milliseconds: 400)) {
          matched = line;
        } else {
          break;
        }
      }
      if (matched != null) {
        return matched.timestamp;
      }
    }
    final maxStart = trackDuration - MomentClipWindow.defaultDuration;
    if (maxStart <= Duration.zero) return Duration.zero;
    if (currentPosition > maxStart) return maxStart;
    return currentPosition;
  }

  void _updateWindow(MomentClipWindow next) {
    if (next == _window) return;
    _userAdjustedWindow = true;
    setState(() {
      _window = next;
      _previewPlayheadOffset = Duration.zero;
      _errorMessage = null;
    });
    if (_auditioning) {
      unawaited(_seekForAudition(next.start));
    }
  }

  Future<void> _seekForAudition(Duration position) async {
    try {
      await ref.read(playerControllerProvider.notifier).seek(position);
    } catch (_) {}
  }

  Future<void> _toggleAudition() async {
    if (_auditioning) {
      _stopAudition(restorePlayback: false);
      try {
        await ref.read(playerControllerProvider.notifier).pause();
      } catch (_) {}
      return;
    }

    final snapshot =
        ref.read(playerControllerProvider).value ??
        const PlayerSnapshot(status: PlayerStatus.idle);
    _wasPlayingBeforeAudition = snapshot.status == PlayerStatus.playing;
    final controller = ref.read(playerControllerProvider.notifier);
    setState(() {
      _auditioning = true;
      _previewPlayheadOffset = Duration.zero;
    });

    try {
      await controller.seek(_window.start);
      if (!_wasPlayingBeforeAudition) {
        await controller.resume();
      }
    } catch (_) {}

    _auditionTimer?.cancel();
    _auditionTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted || !_auditioning) return;
      final currentPos =
          ref.read(playerControllerProvider).value?.position ?? Duration.zero;
      if (currentPos >= _window.end) {
        unawaited(_seekForAudition(_window.start));
        setState(() => _previewPlayheadOffset = Duration.zero);
        return;
      }
      final offset = currentPos - _window.start;
      setState(() {
        _previewPlayheadOffset = offset < Duration.zero
            ? Duration.zero
            : offset > _window.duration
            ? _window.duration
            : offset;
      });
    });
  }

  void _stopAudition({required bool restorePlayback}) {
    _auditionTimer?.cancel();
    _auditionTimer = null;
    if (_auditioning && mounted) {
      setState(() {
        _auditioning = false;
        _previewPlayheadOffset = Duration.zero;
      });
    } else {
      _auditioning = false;
    }
    if (restorePlayback && !_wasPlayingBeforeAudition) {
      unawaited(ref.read(playerControllerProvider.notifier).pause());
    }
  }

  Future<MomentExportableAudioSource?> _resolveAudioSource(
    PlayerSnapshot snapshot,
  ) async {
    final controller = ref.read(playerControllerProvider.notifier);
    final sourceUrl = snapshot.sourceUrl?.trim();

    if (sourceUrl != null && sourceUrl.isNotEmpty) {
      final prepared = controller.preparedAudioSourceFor(sourceUrl);
      if (prepared != null && prepared.uri.toString().trim().isNotEmpty) {
        return MomentExportableAudioSource(
          uri: prepared.uri.toString(),
          httpHeaders: prepared.httpHeaders ?? const <String, String>{},
        );
      }
      final remoteTrack = controller.currentRemoteTrackFor(sourceUrl);
      final streamUrl = remoteTrack?.streamUrl?.trim();
      if (streamUrl != null && streamUrl.isNotEmpty) {
        return MomentExportableAudioSource(
          uri: streamUrl,
          httpHeaders: remoteTrack?.httpHeaders ?? const <String, String>{},
        );
      }
    }

    final localTrack = controller.currentLocalTrackFor(snapshot.trackId);
    if (localTrack != null && localTrack.filePath.trim().isNotEmpty) {
      return MomentExportableAudioSource(uri: localTrack.filePath.trim());
    }

    if (sourceUrl != null &&
        sourceUrl.isNotEmpty &&
        (sourceUrl.startsWith('/') ||
            sourceUrl.startsWith('file://') ||
            sourceUrl.startsWith('content://'))) {
      return MomentExportableAudioSource(uri: sourceUrl);
    }

    // Build candidate TrackInfo for disk-cache lookup or on-demand stream
    // resolution (covers restored sessions, Spotify-Connect / remote sync, and
    // streams whose resolved URL wasn't cached in PlayerController memory).
    final trackUrl = _resolveTrackWatchUrl(snapshot);
    if (trackUrl != null) {
      final candidate =
          controller.currentRemoteTrackFor(trackUrl) ??
          TrackInfo(
            id: snapshot.trackId ?? trackUrl,
            title: snapshot.title ?? 'Inútil Music',
            artist: snapshot.artist ?? 'Inútil Music',
            url: trackUrl,
            thumbnailUrl: snapshot.thumbnailUrl,
            duration: snapshot.duration,
            album: snapshot.album,
          );

      // 1. Check disk audio cache first (instant, zero network).
      try {
        final cachedFile = await ref
            .read(remotePlaybackCacheProvider)
            .cachedFile(candidate);
        if (cachedFile != null && await cachedFile.exists()) {
          return MomentExportableAudioSource(uri: cachedFile.path);
        }
      } catch (_) {}

      // 2. Resolve direct audio stream URL + headers on-demand.
      try {
        final resolved = await ref
            .read(audioStreamResolverProvider)
            .resolve(candidate);
        final uri = resolved.streamUrl.trim();
        if (uri.isNotEmpty) {
          return MomentExportableAudioSource(
            uri: uri,
            httpHeaders: resolved.httpHeaders ?? const <String, String>{},
          );
        }
      } catch (e) {
        debugPrint('Moment audio stream resolution failed: $e');
      }
    }
    return null;
  }

  String? _resolveTrackWatchUrl(PlayerSnapshot snapshot) {
    final sourceUrl = snapshot.sourceUrl?.trim();
    if (sourceUrl != null &&
        (sourceUrl.startsWith('http://') || sourceUrl.startsWith('https://'))) {
      return sourceUrl;
    }
    final trackId = snapshot.trackId?.trim();
    if (trackId != null &&
        RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(trackId)) {
      return 'https://music.youtube.com/watch?v=$trackId';
    }
    return null;
  }

  String _currentExportSignature(
    PlayerSnapshot snapshot,
    Duration lyricsOffset,
    bool lyricsCentered,
  ) =>
      '${snapshot.trackId}|${_mode.wireValue}|${_window.start.inMilliseconds}|${_window.end.inMilliseconds}|${lyricsOffset.inMilliseconds}|$lyricsCentered|${widget.videoUri}';

  Future<void> _exportAndDeliver({required bool share}) async {
    if (_exporting) return;
    final strings = ref.read(appStringsProvider);
    final snapshot =
        _frozenSnapshot ??
        ref.read(playerControllerProvider).value ??
        const PlayerSnapshot(status: PlayerStatus.idle);
    final service = ref.read(momentClipExportServiceProvider);

    _stopAudition(restorePlayback: false);
    if (ref.read(playerControllerProvider).value?.status == PlayerStatus.playing) {
      unawaited(ref.read(playerControllerProvider.notifier).pause());
    }

    final lyricsDoc = _frozenLyrics ?? ref.read(currentLyricsDocumentProvider);
    final lyricsOffset = _frozenLyrics != null
        ? _frozenLyricsOffset
        : ref.read(lyricsOffsetControllerProvider);
    final settings = ref.read(settingsControllerProvider).value;
    final lyricsCentered =
        settings?.lyricsTextAlignment == LyricsTextAlignment.centered;
    final artwork = ref.read(playbackArtworkProvider);
    final visualCache = ref.read(playbackVisualCacheProvider);
    final preferredArt = _frozenArtworkSource ?? widget.artworkSource ?? artwork.source;
    final resolvedArtwork = preferredArt == null
        ? null
        : (visualCache.coverPathFor(preferredArt) ?? preferredArt);
    final accentColor =
        _frozenAccentColor ??
        widget.accentColor ??
        ref.read(playbackArtworkColorProvider) ??
        const Color(0xFF6C8CFF);

    final signature = _currentExportSignature(
      snapshot,
      lyricsOffset,
      lyricsCentered,
    );

    final title = (snapshot.title ?? '').trim().isNotEmpty
        ? snapshot.title!.trim()
        : 'Inútil Music';
    final artist = (snapshot.artist ?? '').trim().isNotEmpty
        ? snapshot.artist!.trim()
        : 'Inútil Music';

    MomentClipExportResult? result;
    if (_cachedSignature == signature && _cachedResult != null) {
      result = _cachedResult;
    } else {
      final jobId = 'moment_${DateTime.now().microsecondsSinceEpoch}';
      setState(() {
        _exporting = true;
        _activeJobId = jobId;
        _exportStage = MomentExportStage.preparing;
        _exportProgress = 0.02;
        _errorMessage = null;
      });

      final audioSource = await _resolveAudioSource(snapshot);
      if (!mounted) return;
      if (audioSource == null || !audioSource.isValid) {
        setState(() {
          _exporting = false;
          _activeJobId = null;
          _errorMessage = strings.shareMomentNoAudio;
        });
        return;
      }

      final request = MomentClipExportRequest(
        jobId: jobId,
        mode: _mode,
        title: title,
        artist: artist,
        album: snapshot.album,
        audioSource: audioSource,
        videoUri: widget.videoUri,
        videoStartOffset: widget.videoStartOffset,
        artworkSource: resolvedArtwork ?? widget.artworkFallbackSource,
        accentColorArgb: accentColor.toARGB32(),
        start: _window.start,
        end: _window.end,
        trackDuration: _window.trackDuration,
        lyricsOffset: lyricsOffset,
        lyricsCentered: lyricsCentered,
        lyricsProviderLabel: lyricsDoc?.provider,
        lyrics: lyricsDoc?.lines ?? const <LyricLine>[],
      );

      try {
        result = await service.exportMoment(
          request,
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              _exportStage = p.stage;
              _exportProgress = p.progress;
            });
          },
        );
        _cachedSignature = signature;
        _cachedResult = result;
      } on MomentExportCancelledException {
        if (mounted) {
          setState(() {
            _exporting = false;
            _activeJobId = null;
          });
        }
        return;
      } catch (e) {
        debugPrint('Moment clip export failed: $e');
        if (mounted) {
          setState(() {
            _exporting = false;
            _activeJobId = null;
            _errorMessage = strings.shareMomentFailed;
          });
        }
        return;
      } finally {
        if (mounted) {
          setState(() {
            _exporting = false;
            _activeJobId = null;
          });
        }
      }
    }

    if (!mounted || result == null) return;

    try {
      if (share) {
        final origin = _shareOriginRect();
        await service.shareClip(
          filePath: result.outputPath,
          title: '$title - $artist',
          sharePositionOrigin: origin,
        );
      } else {
        final saved = await service.saveClip(
          filePath: result.outputPath,
          title: '$title - $artist',
        );
        if (mounted && saved != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.shareMomentSaved)),
          );
        }
      }
    } catch (e) {
      debugPrint('Moment clip delivery failed: $e');
      if (mounted) {
        setState(() => _errorMessage = strings.shareMomentFailed);
      }
    }
  }

  Rect _shareOriginRect() {
    final box =
        _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _cancelActiveExport() async {
    final jobId = _activeJobId;
    await ref.read(momentClipExportServiceProvider).cancelExport(jobId: jobId);
  }

  String _stageLabel(AppStrings strings) => switch (_exportStage) {
    MomentExportStage.preparing => strings.shareMomentStagePreparing,
    MomentExportStage.audio => strings.shareMomentStageAudio,
    MomentExportStage.video =>
      _exportProgress > 0.90
          ? strings.shareMomentStageFinalizing
          : strings.shareMomentStageVideo,
    MomentExportStage.done => strings.shareMomentStageFinalizing,
  };

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final liveSnapshot = ref.watch(playerControllerProvider).value;
    final snapshot =
        _frozenSnapshot ??
        liveSnapshot ??
        const PlayerSnapshot(status: PlayerStatus.idle);
    final lyricsDoc = _frozenLyrics ?? ref.watch(currentLyricsDocumentProvider);
    final lyricsOffset = _frozenLyrics != null
        ? _frozenLyricsOffset
        : ref.watch(lyricsOffsetControllerProvider);
    final artwork = ref.watch(playbackArtworkProvider);
    final accent =
        _frozenAccentColor ??
        widget.accentColor ??
        ref.watch(playbackArtworkColorProvider) ??
        const Color(0xFF6C8CFF);
    final title = (snapshot.title ?? '').trim().isNotEmpty
        ? snapshot.title!.trim()
        : 'Inútil Music';
    final artist = (snapshot.artist ?? '').trim().isNotEmpty
        ? snapshot.artist!.trim()
        : 'Inútil Music';
    final artworkSource =
        _frozenArtworkSource ?? widget.artworkSource ?? artwork.source;
    final artworkFallback =
        _frozenArtworkFallback ?? widget.artworkFallbackSource ?? artwork.fallback;
    final lyrics = lyricsDoc?.lines ?? const <LyricLine>[];
    final previewSongTime = _window.start + _previewPlayheadOffset;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF07090D),
        body: SafeArea(
          child: Column(
            children: [
              // Top header: close, title, HD capability pill.
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 14, 4),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('moment-share-close'),
                      tooltip: strings.close,
                      color: Colors.white,
                      onPressed: _exporting
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        strings.shareMoment,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.hd_rounded,
                            size: 15,
                            color: accent.withValues(alpha: 0.95),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _capabilities.badgeLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Visual mode switcher pills (Letras / Reproductor).
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 4,
                ),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      _ModePill(
                        key: const ValueKey('moment-mode-lyrics'),
                        label: strings.shareMomentModeLyrics,
                        icon: Icons.lyrics_rounded,
                        selected: _mode == MomentClipMode.lyrics,
                        onTap: _exporting
                            ? null
                            : () => setState(() {
                                _mode = MomentClipMode.lyrics;
                                _errorMessage = null;
                              }),
                      ),
                      _ModePill(
                        key: const ValueKey('moment-mode-player'),
                        label: strings.shareMomentModePlayer,
                        icon: Icons.play_circle_outline_rounded,
                        selected: _mode == MomentClipMode.player,
                        onTap: _exporting
                            ? null
                            : () => setState(() {
                                _mode = MomentClipMode.player;
                                _errorMessage = null;
                              }),
                      ),
                    ],
                  ),
                ),
              ),

              // Live 9:16 vertical clip preview canvas.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 9 / 16,
                      child: GestureDetector(
                        onTap: _exporting ? null : _toggleAudition,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.22),
                                blurRadius: 30,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _MomentLivePreviewCard(
                                  mode: _mode,
                                  title: title,
                                  artist: artist,
                                  album: snapshot.album,
                                  artworkSource: artworkSource,
                                  artworkFallbackSource: artworkFallback,
                                  videoUri: widget.videoUri,
                                  videoStartOffset: widget.videoStartOffset,
                                  accentColor: accent,
                                  lyrics: lyrics,
                                  lyricsOffset: lyricsOffset,
                                  songTime: previewSongTime,
                                  trackDuration: _window.trackDuration,
                                  isPlayingVideo: !_exporting,
                                ),
                                // Compact circular audition toggle at top-right (never obscures centered header text).
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: Material(
                                    color: Colors.black.withValues(alpha: 0.48),
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: _exporting
                                          ? null
                                          : _toggleAudition,
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Icon(
                                          _auditioning
                                              ? Icons.pause_rounded
                                              : Icons.volume_up_rounded,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Quick lyric-line anchor chips (when lyrics exist).
              if (lyrics.isNotEmpty)
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    scrollDirection: Axis.horizontal,
                    itemCount: lyrics.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final line = lyrics[index];
                      final isAnchor =
                          (line.timestamp - _window.start).abs() <
                          const Duration(milliseconds: 650);
                      return ActionChip(
                        key: ValueKey('moment-lyric-anchor-$index'),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: isAnchor
                            ? Colors.white.withValues(alpha: 0.22)
                            : Colors.white.withValues(alpha: 0.08),
                        side: BorderSide(
                          color: isAnchor
                              ? Colors.white.withValues(alpha: 0.55)
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                        label: Text(
                          line.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isAnchor
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
                            fontWeight: isAnchor
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        onPressed: _exporting
                            ? null
                            : () => _updateWindow(
                                _window.withStart(line.timestamp),
                              ),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 10),

              // Trimmer section: duration presets + interactive glowing range bar.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${formatDuration(_window.start)} – ${formatDuration(_window.end)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const Spacer(),
                        ...MomentClipWindow.durationPresets.map((preset) {
                          final disabled =
                              _exporting || preset > _window.trackDuration;
                          final selected = _window.duration == preset;
                          return Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: ChoiceChip(
                              key: ValueKey(
                                'moment-duration-${preset.inSeconds}s',
                              ),
                              label: Text('${preset.inSeconds}s'),
                              selected: selected,
                              visualDensity: VisualDensity.compact,
                              labelStyle: TextStyle(
                                color: selected
                                    ? Colors.black
                                    : Colors.white.withValues(
                                        alpha: disabled ? 0.35 : 0.85,
                                      ),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              selectedColor: Colors.white,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.10,
                              ),
                              side: BorderSide.none,
                              showCheckmark: false,
                              onSelected: disabled
                                  ? null
                                  : (_) => _updateWindow(
                                      _window.withDuration(preset),
                                    ),
                            ),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _MomentTimelineTrimmer(
                      window: _window,
                      playheadOffset: _auditioning
                          ? _previewPlayheadOffset
                          : null,
                      accentColor: accent,
                      enabled: !_exporting,
                      onStartChanged: (start) =>
                          _updateWindow(_window.withStart(start)),
                    ),
                  ],
                ),
              ),

              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFF8A80),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              // Bottom export controls or live export progress.
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                child: _exporting
                    ? _ExportProgressBar(
                        label: _stageLabel(strings),
                        progress: _exportProgress,
                        accentColor: accent,
                        cancelLabel: strings.cancel,
                        onCancel: _cancelActiveExport,
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const ValueKey('moment-save-button'),
                              onPressed: () =>
                                  unawaited(_exportAndDeliver(share: false)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.24),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(
                                Icons.download_rounded,
                                size: 20,
                              ),
                              label: Text(
                                strings.shareMomentSaveAction,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              key: _shareButtonKey,
                              onPressed: () =>
                                  unawaited(_exportAndDeliver(share: true)),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(
                                Icons.ios_share_rounded,
                                size: 20,
                              ),
                              label: Text(
                                strings.shareMomentShareAction,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.black : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MomentLivePreviewCard extends StatelessWidget {
  const _MomentLivePreviewCard({
    required this.mode,
    required this.title,
    required this.artist,
    required this.album,
    required this.artworkSource,
    required this.artworkFallbackSource,
    required this.videoUri,
    required this.videoStartOffset,
    required this.accentColor,
    required this.lyrics,
    required this.lyricsOffset,
    required this.songTime,
    required this.trackDuration,
    required this.isPlayingVideo,
  });

  final MomentClipMode mode;
  final String title;
  final String artist;
  final String? album;
  final String? artworkSource;
  final String? artworkFallbackSource;
  final Uri? videoUri;
  final Duration videoStartOffset;
  final Color accentColor;
  final List<LyricLine> lyrics;
  final Duration lyricsOffset;
  final Duration songTime;
  final Duration trackDuration;
  final bool isPlayingVideo;

  int _activeLyricIndex() {
    if (lyrics.isEmpty) return -1;
    final clock = songTime + lyricsOffset;
    var active = 0;
    for (var i = 0; i < lyrics.length; i++) {
      if (lyrics[i].timestamp <= clock) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  @override
  Widget build(BuildContext context) {
    final activeIdx = _activeLyricIndex();
    final progress = trackDuration > Duration.zero
        ? (songTime.inMilliseconds / trackDuration.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Blurred artwork backdrop (always underneath).
        ColoredBox(
          color: const Color(0xFF0A0C10),
          child: artworkSource != null
              ? ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: SourceImage(
                    source: artworkSource,
                    fallbackSource: artworkFallbackSource,
                    fit: BoxFit.cover,
                    fallback: const ColoredBox(color: Color(0xFF0A0C10)),
                  ),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accentColor.withValues(alpha: 0.45),
                        const Color(0xFF0A0C10),
                      ],
                    ),
                  ),
                ),
        ),

        // 2. Live looping Canvas / Video Preview when available.
        if (videoUri != null)
          SpotifyCanvasVideo(
            url: videoUri!,
            isPlaying: isPlayingVideo,
            startOffset: videoStartOffset,
            durationHint: trackDuration,
            revealDuration: const Duration(milliseconds: 300),
          ),

        // 3. Atmospheric readability scrim.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: mode == MomentClipMode.lyrics
                  ? [
                      Colors.black.withValues(alpha: 0.56),
                      Colors.black.withValues(alpha: 0.42),
                      Colors.black.withValues(alpha: 0.62),
                    ]
                  : [
                      Colors.black.withValues(alpha: 0.36),
                      Colors.black.withValues(alpha: 0.12),
                      Colors.black.withValues(alpha: 0.82),
                    ],
            ),
          ),
        ),

        // 4. Mode-specific foreground preview.
        if (mode == MomentClipMode.lyrics)
          _buildLyricsPreview(activeIdx, progress)
        else
          _buildPlayerPreview(activeIdx, progress),

        // 5. Subtle translucent Inútil Music watermark pill at bottom-center.
        Positioned(
          left: 8,
          right: 8,
          bottom: 10,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C0E14).withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                    width: 0.7,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: 0.62,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.asset(
                          'assets/icons/inutil_icon.png',
                          width: 14,
                          height: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Inútil Music',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.56),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLyricsPreview(int activeIdx, double progress) {
    final visibleLines = <({String text, bool active, bool past})>[];
    if (lyrics.isNotEmpty && activeIdx >= 0) {
      final start = math.max(0, activeIdx - 1);
      final end = math.min(lyrics.length - 1, activeIdx + 3);
      for (var i = start; i <= end; i++) {
        visibleLines.add((
          text: lyrics[i].text,
          active: i == activeIdx,
          past: i < activeIdx,
        ));
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: SourceImage(
                    source: artworkSource,
                    fallbackSource: artworkFallbackSource,
                    fit: BoxFit.cover,
                    fallback: const ColoredBox(color: Colors.white12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: Colors.white.withValues(alpha: 0.24),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const Spacer(),
          if (visibleLines.isNotEmpty)
            ...visibleLines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  line.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: line.active
                        ? Colors.white
                        : Colors.white.withValues(
                            alpha: line.past ? 0.30 : 0.44,
                          ),
                    fontSize: line.active ? 16 : 14,
                    fontWeight: FontWeight.w800,
                    height: 1.18,
                    shadows: line.active
                        ? [
                            Shadow(
                              color: accentColor.withValues(alpha: 0.65),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            )
          else
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 110,
                  height: 110,
                  child: SourceImage(
                    source: artworkSource,
                    fallbackSource: artworkFallbackSource,
                    fit: BoxFit.cover,
                    fallback: const ColoredBox(color: Colors.white12),
                  ),
                ),
              ),
            ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildPlayerPreview(int activeIdx, double progress) {
    final activeText = (activeIdx >= 0 && activeIdx < lyrics.length)
        ? lyrics[activeIdx].text
        : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Text(
                  album?.trim().isNotEmpty == true ? album! : 'REPRODUCIENDO',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (activeText.isNotEmpty) ...[
            Text(
              activeText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                height: 1.18,
                shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: SourceImage(
                    source: artworkSource,
                    fallbackSource: artworkFallbackSource,
                    fit: BoxFit.cover,
                    fallback: const ColoredBox(color: Colors.white12),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(songTime),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                formatDuration(trackDuration),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Interactive Reels/WhatsApp-style draggable timeline window bar.
class _MomentTimelineTrimmer extends StatelessWidget {
  const _MomentTimelineTrimmer({
    required this.window,
    required this.playheadOffset,
    required this.accentColor,
    required this.enabled,
    required this.onStartChanged,
  });

  final MomentClipWindow window;
  final Duration? playheadOffset;
  final Color accentColor;
  final bool enabled;
  final ValueChanged<Duration> onStartChanged;

  void _updateFromLocalX(double dx, double width) {
    if (!enabled || width <= 0) return;
    final totalMs = window.trackDuration.inMilliseconds;
    final winMs = window.duration.inMilliseconds;
    if (totalMs <= winMs) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    // Center the window around the user's touch point.
    final centerMs = (fraction * totalMs).round();
    final newStartMs = (centerMs - winMs ~/ 2).clamp(0, totalMs - winMs);
    onStartChanged(Duration(milliseconds: newStartMs));
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = window.trackDuration.inMilliseconds.clamp(1, 1 << 30);
    final startFrac = (window.start.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final widthFrac = (window.duration.inMilliseconds / totalMs).clamp(
      0.06,
      1.0,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final barW = constraints.maxWidth;
        final winLeft = (startFrac * barW).clamp(0.0, barW);
        final winW = (widthFrac * barW).clamp(24.0, barW);
        final clampedLeft = math.min(winLeft, math.max(0.0, barW - winW));

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _updateFromLocalX(d.localPosition.dx, barW),
          onHorizontalDragUpdate: (d) =>
              _updateFromLocalX(d.localPosition.dx, barW),
          child: SizedBox(
            height: 46,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Waveform bars background.
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(38, (i) {
                      final norm = 0.25 +
                          0.65 *
                              (0.5 +
                                  0.5 *
                                      math.sin(i * 0.72) *
                                      math.cos(i * 0.31));
                      return Container(
                        width: 3,
                        height: 28 * norm,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.24),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                  ),
                ),

                // Highlighted draggable clip window.
                Positioned(
                  left: clampedLeft,
                  width: winW,
                  top: 3,
                  bottom: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.26),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 2.2),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.35),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        if (playheadOffset != null)
                          Positioned(
                            left:
                                ((playheadOffset!.inMilliseconds /
                                            window.duration.inMilliseconds
                                                .clamp(1, 1 << 30))
                                        .clamp(0.0, 1.0)) *
                                    math.max(0.0, winW - 6),
                            top: 2,
                            bottom: 2,
                            child: Container(
                              width: 2.5,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ExportProgressBar extends StatelessWidget {
  const _ExportProgressBar({
    required this.label,
    required this.progress,
    required this.accentColor,
    required this.cancelLabel,
    required this.onCancel,
  });

  final String label;
  final double progress;
  final Color accentColor;
  final String cancelLabel;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).round().clamp(0, 100);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.02, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      accentColor.computeLuminance() < 0.25
                          ? Colors.white
                          : accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: const ValueKey('moment-export-cancel'),
            onPressed: onCancel,
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            child: Text(cancelLabel),
          ),
        ],
      ),
    );
  }
}

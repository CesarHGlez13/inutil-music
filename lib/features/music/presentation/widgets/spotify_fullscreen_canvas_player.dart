part of 'player_panel.dart';

/// Full-screen edge-to-edge Spotify Canvas player layout:
/// looping muted video fills 100% of the viewport behind a Spotify-style
/// top bar, floating live synced lyric line, mini cover + title + circular
/// favorite button, crisp white timeline, large white circular play/pause
/// button, device/share/queue bar, and a bottom "Muestra de la letra" card.
class _SpotifyFullscreenCanvasPlayer extends ConsumerWidget {
  const _SpotifyFullscreenCanvasPlayer({
    required this.snapshot,
    required this.artworkSource,
    required this.artworkFallbackSource,
    required this.visualIdentity,
    required this.trackTransitionsEnabled,
    required this.canvasUrl,
    required this.videoStartOffset,
    required this.videoDurationHint,
    required this.hasTrack,
    required this.isFavorite,
    required this.savedTrackId,
    required this.hasError,
    required this.errorText,
    required this.queueVisible,
    required this.onToggleQueue,
    required this.onCollapse,
    required this.onOpenLyrics,
    required this.onOpenSearch,
    required this.onOpenArtist,
    required this.onOpenAlbum,
    required this.strings,
  });

  static const _spotifyGreen = Color(0xFF1DB954);

  final PlayerSnapshot snapshot;
  final String? artworkSource;
  final String? artworkFallbackSource;
  final String visualIdentity;
  final bool trackTransitionsEnabled;
  final Uri? canvasUrl;
  final Duration videoStartOffset;
  final Duration videoDurationHint;
  final bool hasTrack;
  final bool isFavorite;
  final String? savedTrackId;
  final bool hasError;
  final String? errorText;
  final bool queueVisible;
  final VoidCallback onToggleQueue;
  final VoidCallback? onCollapse;
  final VoidCallback onOpenLyrics;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onOpenArtist;
  final VoidCallback? onOpenAlbum;
  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topInset = _playerTopSafeInset(context);
    final bottomInset = math.max(
      MediaQuery.viewPaddingOf(context).bottom,
      MediaQuery.paddingOf(context).bottom,
    );
    final isPlaying = snapshot.status == PlayerStatus.playing;
    final player = ref.read(playerControllerProvider.notifier);
    final syncService = ref.watch(inutilPlaybackSyncProvider);
    final pairedDeviceName = syncService.autoPairedPeer?.deviceName;
    final sleepTimer = ref.watch(sleepTimerControllerProvider);
    final shareTrack = snapshot.isExternal
        ? null
        : _shareTrackForSnapshot(
            snapshot,
            ref,
            strings,
            savedTrackId: savedTrackId,
          );
    final artistLabel = (snapshot.artist ?? '').trim().isNotEmpty
        ? snapshot.artist!.trim()
        : 'Inútil Music';

    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final backdropFadeDuration = disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 850);
    final videoRevealDuration = disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 950);
    final miniArtFadeDuration = disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 500);
    final activeCanvasUrl = canvasUrl;

    return Stack(
      key: const ValueKey('spotify-fullscreen-canvas-player'),
      fit: StackFit.expand,
      children: [
        // 1. Soft blurred ambient cover backdrop that cross-fades slowly
        // while the video buffers or while skipping between tracks.
        Positioned.fill(
          child: ColoredBox(
            color: const Color(0xFF0A0C10),
            child: AnimatedSwitcher(
              duration: backdropFadeDuration,
              reverseDuration: backdropFadeDuration,
              switchInCurve: Curves.easeInOutCubic,
              switchOutCurve: Curves.easeInOutCubic,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                fit: StackFit.expand,
                children: [...previousChildren, ?currentChild],
              ),
              child: artworkSource?.trim().isNotEmpty == true
                  ? RepaintBoundary(
                      key: ValueKey('canvas-backdrop-${artworkSource ?? visualIdentity}'),
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: 18,
                          sigmaY: 18,
                          tileMode: TileMode.mirror,
                        ),
                        child: ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            const Color(0xFF0A0C10).withValues(alpha: 0.36),
                            BlendMode.darken,
                          ),
                          child: ProportionalArtwork(
                            source: artworkSource,
                            fallbackSource: artworkFallbackSource,
                            cacheWidth: 256,
                            fallback: const ColoredBox(color: Color(0xFF0A0C10)),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.expand(
                      key: ValueKey('canvas-backdrop-empty'),
                    ),
            ),
          ),
        ),

        // 2. Full-bleed edge-to-edge looping muted video Canvas with slow fade-in.
        Positioned.fill(
          key: const ValueKey('player-canvas-viewport'),
          child: IgnorePointer(
            child: AnimatedSwitcher(
              duration: disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 650),
              reverseDuration: disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 500),
              switchInCurve: Curves.easeInOutCubic,
              switchOutCurve: Curves.easeInOutCubic,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                fit: StackFit.expand,
                children: [...previousChildren, ?currentChild],
              ),
              child: activeCanvasUrl != null
                  ? SpotifyCanvasVideo(
                      key: const ValueKey('fullscreen-canvas-video'),
                      url: activeCanvasUrl,
                      isPlaying: isPlaying,
                      identity: visualIdentity,
                      startOffset: videoStartOffset,
                      durationHint: videoDurationHint,
                      revealDuration: videoRevealDuration,
                      revealCurve: Curves.easeInOutCubic,
                    )
                  : const SizedBox.expand(
                      key: ValueKey('fullscreen-canvas-pending'),
                    ),
            ),
          ),
        ),

        // 3. Cinematic readability scrim (clear center window for video).
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.62),
                    Colors.black.withValues(alpha: 0.14),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.52),
                    Colors.black.withValues(alpha: 0.90),
                    Colors.black.withValues(alpha: 0.96),
                  ],
                  stops: const [0.0, 0.16, 0.36, 0.58, 0.78, 1.0],
                ),
              ),
            ),
          ),
        ),

        // 4. Foreground Spotify layout.
        Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            topInset + 4,
            20,
            bottomInset + 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top bar: Collapse, "Reproduciendo desde Artista", Menu.
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('spotify-canvas-collapse'),
                    tooltip: strings.minimizePlayer,
                    onPressed: onCollapse,
                    color: Colors.white,
                    iconSize: 30,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: onOpenArtist,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Reproduciendo desde Artista',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              artistLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!snapshot.isExternal)
                    _PlayerMenu(
                      snapshot: snapshot,
                      isFavorite: isFavorite,
                      savedTrackId: savedTrackId,
                      onOpenSearch: onOpenSearch,
                      onOpenArtist: onOpenArtist,
                      onOpenAlbum: onOpenAlbum,
                      strings: strings,
                      compact: true,
                    )
                  else
                    const SizedBox(width: 40),
                ],
              ),

              // Open center window so the full-bleed artist video shines.
              const Spacer(),

              // Live floating synced lyric line right over the video.
              _CanvasFloatingLyricLine(onTap: onOpenLyrics),
              const SizedBox(height: 18),

              // Track row: mini cover + bold title/artist + circular +/check.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox.square(
                      dimension: 48,
                      child: AnimatedSwitcher(
                        duration: miniArtFadeDuration,
                        switchInCurve: Curves.easeInOutCubic,
                        switchOutCurve: Curves.easeInOutCubic,
                        layoutBuilder: (currentChild, previousChildren) => Stack(
                          fit: StackFit.expand,
                          children: [...previousChildren, ?currentChild],
                        ),
                        child: KeyedSubtree(
                          key: ValueKey('canvas-mini-art-${artworkSource ?? visualIdentity}'),
                          child: ProportionalArtwork(
                            source: artworkSource,
                            fallbackSource: artworkFallbackSource,
                            cacheWidth: 160,
                            fallback: const ColoredBox(
                              color: Color(0xFF1F2430),
                              child: Icon(
                                Icons.music_note_rounded,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TrackChangeTransition(
                      switcherKey: const ValueKey(
                        'spotify-canvas-metadata-transition',
                      ),
                      identity: visualIdentity,
                      enabled: trackTransitionsEnabled,
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MarqueeText(
                            key: const ValueKey('player-track-title'),
                            snapshot.title ?? strings.noPlayback,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          InkWell(
                            key: const ValueKey('player-track-artist-action'),
                            onTap: onOpenArtist,
                            child: Text(
                              artistLabel,
                              key: const ValueKey('player-track-artist'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (!snapshot.isExternal)
                    _SpotifyCircleFavoriteButton(
                      snapshot: snapshot,
                      isFavorite: isFavorite,
                      savedTrackId: savedTrackId,
                      strings: strings,
                    ),
                ],
              ),

              const SizedBox(height: 16),

              // Crisp white progress bar with timestamps.
              _AppleMusicTimeline(
                strings: strings,
                compact: true,
                trackHeight: 3,
                sliderHeight: 22,
                showThumb: true,
                sliderKey: const ValueKey('spotify-player-linear-seek'),
              ),

              const SizedBox(height: 10),

              // Main Spotify transport controls.
              Row(
                key: const ValueKey('spotify-player-transport'),
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SpotifyToggleControl(
                    key: const ValueKey('player-shuffle-control'),
                    tooltip: snapshot.shuffleEnabled
                        ? strings.deactivateShuffle
                        : strings.activateShuffle,
                    icon: Icons.shuffle_rounded,
                    active: snapshot.shuffleEnabled,
                    activeColor: _spotifyGreen,
                    onPressed: hasTrack ? () => player.toggleShuffle() : null,
                  ),
                  IconButton(
                    key: const ValueKey('player-previous-control'),
                    tooltip: strings.previous,
                    color: Colors.white,
                    disabledColor: Colors.white38,
                    iconSize: 38,
                    onPressed: hasTrack ? () => player.playPrevious() : null,
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  SizedBox.square(
                    dimension: 66,
                    child: IconButton(
                      key: const ValueKey('player-primary-control'),
                      tooltip: isPlaying ? strings.pause : strings.play,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white38,
                        shape: const CircleBorder(),
                      ),
                      color: Colors.black,
                      disabledColor: Colors.black45,
                      iconSize: 38,
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      onPressed:
                          hasTrack ? () => player.togglePlayPause() : null,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('player-next-control'),
                    tooltip: strings.next,
                    color: Colors.white,
                    disabledColor: Colors.white38,
                    iconSize: 38,
                    onPressed: hasTrack ? () => player.playNext() : null,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                  _SpotifyToggleControl(
                    key: const ValueKey('player-repeat-control'),
                    tooltip: switch (snapshot.repeatMode) {
                      PlaybackRepeatMode.off => strings.repeatQueue,
                      PlaybackRepeatMode.all => strings.repeatOne,
                      PlaybackRepeatMode.one => strings.disableRepeat,
                    },
                    icon: snapshot.repeatMode == PlaybackRepeatMode.one
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                    active: snapshot.repeatMode != PlaybackRepeatMode.off,
                    activeColor: _spotifyGreen,
                    onPressed:
                        hasTrack ? () => player.cycleRepeatMode() : null,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Bottom utility row: Devices (left), Sleep Timer + Share + Queue (right).
              Row(
                children: [
                  InkWell(
                    onTap: () => InutilConnectSheet.show(context),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InutilIcon(
                            InutilGlyph.devices,
                            size: 21,
                            filled: pairedDeviceName != null,
                            color: pairedDeviceName != null
                                ? _spotifyGreen
                                : Colors.white.withValues(alpha: 0.88),
                          ),
                          if (pairedDeviceName != null) ...[
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 150),
                              child: Text(
                                pairedDeviceName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _spotifyGreen,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const ValueKey('spotify-canvas-sleep-timer'),
                    tooltip: 'Temporizador de sueño',
                    onPressed: () => InutilSleepTimerSheet.show(context),
                    icon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InutilIcon(
                          InutilGlyph.sleepTimer,
                          size: 21,
                          filled: sleepTimer.isActive,
                          color: sleepTimer.isActive
                              ? _spotifyGreen
                              : Colors.white.withValues(alpha: 0.88),
                        ),
                        if (sleepTimer.isActive) ...[
                          const SizedBox(width: 4),
                          Text(
                            '${sleepTimer.remaining.inMinutes + 1}m',
                            style: const TextStyle(
                              color: _spotifyGreen,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (shareTrack != null)
                    IconButton(
                      tooltip: strings.shareSong,
                      color: Colors.white.withValues(alpha: 0.88),
                      iconSize: 21,
                      onPressed: () => unawaited(
                        _shareTrack(
                          context: context,
                          ref: ref,
                          track: shareTrack,
                          strings: strings,
                        ),
                      ),
                      icon: const Icon(Icons.share_outlined),
                    ),
                  IconButton(
                    tooltip: 'Cola de reproducción',
                    onPressed: onToggleQueue,
                    icon: InutilIcon(
                      InutilGlyph.queue,
                      size: 22,
                      filled: queueVisible,
                      color: queueVisible
                          ? _spotifyGreen
                          : Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
                ],
              ),

              if (hasError) ...[
                const SizedBox(height: 6),
                PlayerErrorMessage(message: errorText ?? strings.playbackError),
              ],

              const SizedBox(height: 8),

              // Bottom "Muestra de la letra" peek card (Spotify style).
              Material(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  key: const ValueKey('spotify-canvas-lyrics-card'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: onOpenLyrics,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Muestra de la letra',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.translate_rounded,
                          size: 19,
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Resolves the active synced lyric line for [position] using binary search
/// over ordered [doc.lines], falling back to the first non-empty line before
/// the initial timestamp.
String activeSyncedLyricLineText(LyricsDocument doc, Duration position) {
  final lines = doc.lines;
  if (lines.isEmpty) return '';
  var low = 0;
  var high = lines.length - 1;
  var upperBound = -1;
  while (low <= high) {
    final mid = (low + high) ~/ 2;
    if (position >= lines[mid].timestamp) {
      upperBound = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  for (var i = upperBound; i >= 0; i--) {
    final candidate = lines[i].text.trim();
    if (candidate.isNotEmpty) return candidate;
  }
  for (final line in lines) {
    final candidate = line.text.trim();
    if (candidate.isNotEmpty) return candidate;
  }
  return '';
}

class _CanvasFloatingLyricLine extends ConsumerWidget {
  const _CanvasFloatingLyricLine({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(currentLyricsDocumentProvider);
    if (doc == null || !doc.hasSyncedLyrics) {
      return const SizedBox.shrink();
    }
    // Select only the resolved lyric line string so 200 ms position ticks
    // do not rebuild or allocate until the active lyric text changes.
    final activeText = ref.watch(
      playerControllerProvider.select(
        (player) => activeSyncedLyricLineText(
          doc,
          player.value?.position ?? Duration.zero,
        ),
      ),
    );
    if (activeText.isEmpty) return const SizedBox.shrink();

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: Align(
            key: ValueKey(activeText),
            alignment: Alignment.centerLeft,
            child: Text(
              activeText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.28,
                shadows: [
                  Shadow(
                    color: Color(0xCC000000),
                    blurRadius: 12,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpotifyToggleControl extends StatelessWidget {
  const _SpotifyToggleControl({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: tooltip,
          color: active ? activeColor : Colors.white.withValues(alpha: 0.78),
          disabledColor: Colors.white30,
          iconSize: 26,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 44, height: 40),
          onPressed: onPressed,
          icon: Icon(icon),
        ),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: active ? 1 : 0,
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: activeColor,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

class _SpotifyCircleFavoriteButton extends ConsumerWidget {
  const _SpotifyCircleFavoriteButton({
    required this.snapshot,
    required this.isFavorite,
    required this.savedTrackId,
    required this.strings,
  });

  static const _spotifyGreen = Color(0xFF1DB954);

  final PlayerSnapshot snapshot;
  final bool isFavorite;
  final String? savedTrackId;
  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasIdentity =
        (snapshot.trackId?.trim().isNotEmpty ?? false) ||
        (snapshot.sourceUrl?.trim().isNotEmpty ?? false);

    return Tooltip(
      message: isFavorite
          ? strings.removeFromFavorites
          : strings.addToFavorites,
      child: InkWell(
        key: const ValueKey('player-favorite-control'),
        customBorder: const CircleBorder(),
        onTap: hasIdentity
            ? () => unawaited(
                _toggleFavoriteForSnapshot(
                  context: context,
                  ref: ref,
                  snapshot: snapshot,
                  isFavorite: isFavorite,
                  savedTrackId: savedTrackId,
                  strings: strings,
                ),
              )
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFavorite ? _spotifyGreen : Colors.transparent,
            border: Border.all(
              color: isFavorite ? _spotifyGreen : Colors.white,
              width: 2,
            ),
          ),
          child: Icon(
            isFavorite ? Icons.check_rounded : Icons.add_rounded,
            size: 20,
            color: isFavorite ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}

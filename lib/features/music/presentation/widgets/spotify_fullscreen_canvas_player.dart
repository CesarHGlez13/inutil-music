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
    this.animatedArtworkEnabled = true,
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

  final PlayerSnapshot snapshot;
  final String? artworkSource;
  final String? artworkFallbackSource;
  final String visualIdentity;
  final bool trackTransitionsEnabled;
  final bool animatedArtworkEnabled;
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
    final pairedDeviceName = syncService.activeRemoteSpeakerName;
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
        : 'Inutix Music';

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
    final artworkAccentColor = artworkSource?.trim().isNotEmpty == true
        ? ref.watch(artworkProgressColorProvider(artworkSource)).value
        : null;
    final settings = ref.watch(settingsControllerProvider).value;
    final dynamicAccentEnabled = settings?.dynamicPlayerAccent ?? false;
    final themePrimary = Theme.of(context).colorScheme.primary;
    final rawAccent = dynamicAccentEnabled
        ? (artworkAccentColor ?? themePrimary)
        : themePrimary;
    final effectiveAccent = rawAccent.computeLuminance() < 0.24
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.35), rawAccent)
        : rawAccent;
    final motionAllowed = !disableAnimations && animatedArtworkEnabled;
    final gestureScope = PlayerGestureScope.maybeOf(context);
    final canvasOffset = gestureScope?.horizontalOffset ?? 0.0;
    final canvasDragFraction = gestureScope?.dragFraction ?? 1.0;

    return Stack(
      key: const ValueKey('spotify-fullscreen-canvas-player'),
      fit: StackFit.expand,
      children: [
        // 1 & 2. Background Canvas & Video Stack.
        // Se traslada interactivamente con el arrastre horizontal del gesto,
        // mientras los controles de reproducción permanecen fijos como en Spotify.
        Positioned.fill(
          child: Transform.translate(
            offset: Offset(canvasOffset, 0),
            child: Opacity(
              opacity: canvasDragFraction,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Generative Mesh Canvas en GPU con gradientes líquidos y partículas
                  // neón reactivas que aseguran 100% de cobertura visual sin depender
                  // de scrapers externos caídos ni consumir datos móviles.
                  Positioned.fill(
                    child: GenerativeMeshCanvas(
                      primaryColor: artworkAccentColor ?? effectiveAccent,
                      secondaryColor: effectiveAccent,
                      isPlaying: isPlaying,
                    ),
                  ),

                  // 1b. Crisp animated full-bleed artwork Canvas layer (solo como placeholder
                  // temporal mientras carga el video; si no hay video, GenerativeMeshCanvas
                  // permanece 100% visible sin ser tapado por un zoom estático opaco).
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: backdropFadeDuration,
                      reverseDuration: backdropFadeDuration,
                      switchInCurve: Curves.easeInOutCubic,
                      switchOutCurve: Curves.easeInOutCubic,
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        fit: StackFit.expand,
                        children: [...previousChildren, ?currentChild],
                      ),
                      child: activeCanvasUrl != null && artworkSource?.trim().isNotEmpty == true
                          ? RepaintBoundary(
                              key: ValueKey(
                                'canvas-backdrop-${artworkSource ?? visualIdentity}',
                              ),
                              child: AnimatedArtworkMotion(
                                enabled: motionAllowed,
                                isPlaying: isPlaying,
                                identity: visualIdentity,
                                borderRadius: BorderRadius.zero,
                                depthEnabled: false,
                                motionScale: 1.0,
                                zoomDuration: AnimatedArtworkMotion.defaultZoomDuration,
                                panDuration: AnimatedArtworkMotion.defaultPanDuration,
                                child: SourceImage(
                                  source: artworkSource,
                                  fallbackSource: artworkFallbackSource,
                                  fit: BoxFit.cover,
                                  fallback: const SizedBox.shrink(),
                                ),
                              ),
                            )
                          : const SizedBox.expand(
                              key: ValueKey('canvas-backdrop-empty'),
                            ),
                    ),
                  ),

                  // 1b. Dynamic breathing ambient glow when displaying the expanded cover
                  // without a video Canvas; fades out cleanly once a real Canvas video
                  // takes over.
                  if (activeCanvasUrl == null && artworkSource?.trim().isNotEmpty == true)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: _CanvasArtworkAmbientAura(
                          accentColor: artworkAccentColor ?? effectiveAccent,
                          enabled: motionAllowed,
                          isPlaying: isPlaying,
                        ),
                      ),
                    ),

                  // 2. Full-bleed edge-to-edge looping muted video Canvas that fades in
                  // smoothly over the animated cover once frame 1 is decoded.
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
                ],
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

        // 4. Foreground Spotify layout:
        // On desktop windows (wide layout), render full desktop width with the
        // bottom control deck adopting the exact capsule, liquid glass, and
        // 3-section layout of the desktop mini reproductor.
        LayoutBuilder(
          builder: (context, constraints) {
            final compactMobile = AppPlatform.isMobileTargetPlatform(
              Theme.of(context).platform,
            );
            final isDesktop = AppPlatform.isDesktop && !compactMobile;
            final isWideDesktop = isDesktop && constraints.maxWidth >= 720;
            final isWideCanvas = constraints.maxWidth >= 720;

            if (isWideDesktop) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top bar (desktop): Botón Atrás + Reproduciendo desde Artista + Menú.
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      32,
                      topInset + 14,
                      32,
                      0,
                    ),
                    child: Row(
                      children: [
                        Material(
                          color: Colors.white.withValues(alpha: 0.12),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: const ValueKey('spotify-canvas-collapse'),
                            onTap: onCollapse,
                            child: Tooltip(
                              message: strings.back,
                              child: const SizedBox.square(
                                dimension: 40,
                                child: Icon(
                                  Icons.arrow_back_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        InkWell(
                          onTap: onOpenArtist,
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Reproduciendo desde Artista',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  artistLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
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
                          ),
                      ],
                    ),
                  ),

                  // Open center window with live synced lyrics over Canvas video
                  Expanded(
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: activeCanvasUrl == null &&
                                artworkSource?.trim().isNotEmpty == true
                            ? Transform.translate(
                                offset: Offset(canvasOffset, 0),
                                child: Opacity(
                                  opacity: canvasDragFraction,
                                  child: Padding(
                                    key: ValueKey('desktop-canvas-center-art-${artworkSource ?? visualIdentity}'),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        maxWidth: 240.0,
                                        maxHeight: 240.0,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(24),
                                        boxShadow: [
                                          BoxShadow(
                                            color: (artworkAccentColor ?? effectiveAccent).withValues(alpha: 0.38),
                                            blurRadius: 36,
                                            spreadRadius: 2,
                                            offset: const Offset(0, 12),
                                          ),
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.60),
                                            blurRadius: 20,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(24),
                                        child: AspectRatio(
                                          aspectRatio: 1.0,
                                          child: SourceImage(
                                            source: artworkSource,
                                            fallbackSource: artworkFallbackSource,
                                            fit: BoxFit.cover,
                                            fallback: const SizedBox.shrink(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: _CanvasFloatingLyricLine(
                        onTap: onOpenLyrics,
                        isDesktop: true,
                      ),
                    ),
                  ),
                  const Spacer(),

                  // Desktop controls capsule with the exact same appearance as the mini player!
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      0,
                      24,
                      18 + bottomInset,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1280),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(40),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                            child: Container(
                              height: 104,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x6612161A),
                                borderRadius: BorderRadius.circular(40),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  width: 0.8,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // Left section: 60px artwork + metadata + favorite button
                                  Expanded(
                                    flex: 3,
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: SizedBox.square(
                                            dimension: 60,
                                            child: ProportionalArtwork(
                                              source: artworkSource,
                                              fallbackSource:
                                                  artworkFallbackSource,
                                              cacheWidth: 180,
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
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              MarqueeText(
                                                key: const ValueKey(
                                                  'player-track-title',
                                                ),
                                                snapshot.title ??
                                                    strings.noPlayback,
                                                pause: const Duration(
                                                  milliseconds: 1700,
                                                ),
                                                travel: const Duration(
                                                  milliseconds: 6200,
                                                ),
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.white,
                                                  shadows: [
                                                    Shadow(
                                                      color: Color(0xAA000000),
                                                      blurRadius: 8,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              if (pairedDeviceName != null)
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.speaker_group_rounded,
                                                      size: 13,
                                                      color: Color(0xFF1DB954),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Flexible(
                                                      child: Text(
                                                        pairedDeviceName,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 12.5,
                                                          color:
                                                              Color(0xFF1DB954),
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              else
                                                InkWell(
                                                  key: const ValueKey(
                                                    'player-track-artist-action',
                                                  ),
                                                  onTap: onOpenArtist,
                                                  child: Text(
                                                    artistLabel,
                                                    key: const ValueKey(
                                                      'player-track-artist',
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.78,
                                                          ),
                                                      fontWeight: FontWeight.w500,
                                                      shadows: const [
                                                        Shadow(
                                                          color: Color(0x99000000),
                                                          blurRadius: 7,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (!snapshot.isExternal)
                                          _SpotifyCircleFavoriteButton(
                                            snapshot: snapshot,
                                            isFavorite: isFavorite,
                                            savedTrackId: savedTrackId,
                                            artworkSource: artworkSource,
                                            artworkFallbackSource:
                                                artworkFallbackSource,
                                            accentColor: effectiveAccent,
                                            strings: strings,
                                          ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 16),

                                  // Center section: Transport controls + seek bar
                                  Expanded(
                                    flex: 4,
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _SpotifyToggleControl(
                                                key: const ValueKey(
                                                  'player-shuffle-control',
                                                ),
                                                tooltip: snapshot.shuffleEnabled
                                                    ? strings.deactivateShuffle
                                                    : strings.activateShuffle,
                                                icon: Icons.shuffle_rounded,
                                                active: snapshot.shuffleEnabled,
                                                activeColor: effectiveAccent,
                                                onPressed: hasTrack
                                                    ? () => player.toggleShuffle()
                                                    : null,
                                              ),
                                              IconButton(
                                                key: const ValueKey(
                                                  'player-previous-control',
                                                ),
                                                tooltip: strings.previous,
                                                color: Colors.white,
                                                disabledColor: Colors.white38,
                                                iconSize: 32,
                                                onPressed: hasTrack
                                                    ? () => player.playPrevious()
                                                    : null,
                                                icon: const Icon(
                                                  Icons.skip_previous_rounded,
                                                ),
                                              ),
                                              SizedBox.square(
                                                dimension: 52,
                                                child: IconButton(
                                                  key: const ValueKey(
                                                    'player-primary-control',
                                                  ),
                                                  tooltip: isPlaying
                                                      ? strings.pause
                                                      : strings.play,
                                                  style: IconButton.styleFrom(
                                                    backgroundColor: Colors.white,
                                                    disabledBackgroundColor:
                                                        Colors.white38,
                                                    shape: const CircleBorder(),
                                                  ),
                                                  color: Colors.black,
                                                  disabledColor: Colors.black45,
                                                  iconSize: 32,
                                                  padding: EdgeInsets.zero,
                                                  icon: Icon(
                                                    isPlaying
                                                        ? Icons.pause_rounded
                                                        : Icons.play_arrow_rounded,
                                                  ),
                                                  onPressed: hasTrack
                                                      ? () => player
                                                            .togglePlayPause()
                                                      : null,
                                                ),
                                              ),
                                              IconButton(
                                                key: const ValueKey(
                                                  'player-next-control',
                                                ),
                                                tooltip: strings.next,
                                                color: Colors.white,
                                                disabledColor: Colors.white38,
                                                iconSize: 32,
                                                onPressed: hasTrack
                                                    ? () => player.playNext()
                                                    : null,
                                                icon: const Icon(
                                                  Icons.skip_next_rounded,
                                                ),
                                              ),
                                              _SpotifyToggleControl(
                                                key: const ValueKey(
                                                  'player-repeat-control',
                                                ),
                                                tooltip: switch (
                                                  snapshot.repeatMode
                                                ) {
                                                  PlaybackRepeatMode.off =>
                                                    strings.repeatQueue,
                                                  PlaybackRepeatMode.all =>
                                                    strings.repeatOne,
                                                  PlaybackRepeatMode.one =>
                                                    strings.disableRepeat,
                                                },
                                                icon: snapshot.repeatMode ==
                                                        PlaybackRepeatMode.one
                                                    ? Icons.repeat_one_rounded
                                                    : Icons.repeat_rounded,
                                                active:
                                                    snapshot.repeatMode !=
                                                    PlaybackRepeatMode.off,
                                                activeColor: effectiveAccent,
                                                onPressed: hasTrack
                                                    ? () => player
                                                          .cycleRepeatMode()
                                                    : null,
                                              ),
                                            ],
                                          ),
                                          SizedBox(
                                            height: 24,
                                            child: _AppleMusicTimeline(
                                              strings: strings,
                                              compact: true,
                                              trackHeight: 3,
                                              sliderHeight: 18,
                                              showThumb: true,
                                              sliderKey: const ValueKey(
                                                'spotify-player-linear-seek',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  const SizedBox(width: 16),

                                  // Right section: Utility controls + volume
                                  Expanded(
                                    flex: 3,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        IconButton(
                                          tooltip: strings.lyrics,
                                          color: Colors.white.withValues(
                                            alpha: 0.88,
                                          ),
                                          iconSize: 22,
                                          onPressed: onOpenLyrics,
                                          icon: const PlayerLyricsIcon(),
                                        ),
                                        IconButton(
                                          key: const ValueKey(
                                            'spotify-canvas-sleep-timer',
                                          ),
                                          tooltip: 'Temporizador de sueño',
                                          onPressed: () =>
                                              InutilSleepTimerSheet.show(context),
                                          icon: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              InutilIcon(
                                                InutilGlyph.sleepTimer,
                                                size: 21,
                                                filled: sleepTimer.isActive,
                                                color: sleepTimer.isActive
                                                    ? effectiveAccent
                                                    : Colors.white.withValues(
                                                        alpha: 0.88,
                                                      ),
                                              ),
                                              if (sleepTimer.isActive) ...[
                                                const SizedBox(width: 4),
                                                Text(
                                                  '${sleepTimer.remaining.inMinutes + 1}m',
                                                  style: TextStyle(
                                                    color: effectiveAccent,
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Cola de reproducción',
                                          onPressed: onToggleQueue,
                                          icon: InutilIcon(
                                            InutilGlyph.queue,
                                            size: 22,
                                            filled: queueVisible,
                                            color: queueVisible
                                                ? effectiveAccent
                                                : Colors.white.withValues(
                                                    alpha: 0.88,
                                                  ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: pairedDeviceName != null
                                              ? 'Escuchando en $pairedDeviceName'
                                              : 'Conectar a un dispositivo',
                                          onPressed: () =>
                                              InutilConnectSheet.show(context),
                                          icon: InutilIcon(
                                            InutilGlyph.devices,
                                            size: 21,
                                            filled: pairedDeviceName != null,
                                            color: pairedDeviceName != null
                                                ? effectiveAccent
                                                : Colors.white.withValues(
                                                    alpha: 0.88,
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: _CanvasVolumeControl(
                                            volume: snapshot.volume,
                                          ),
                                        ),
                                      ],
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
                ],
              );
            }

            final foreground = Padding(
              padding: EdgeInsets.fromLTRB(
                isWideCanvas ? 28 : 20,
                topInset + (isWideCanvas ? 12 : 4),
                isWideCanvas ? 28 : 20,
                bottomInset + (isWideCanvas ? 18 : 10),
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

                  const SizedBox(height: 10),
                  _PlayerLiveOverlaysBar(
                    snapshot: snapshot,
                    spanish: strings.language != 'en',
                    accentColor: effectiveAccent,
                  ),

                  // Open center window: if activeCanvasUrl == null, show beautiful centered album art
                  // over the GenerativeMeshCanvas; if activeCanvasUrl != null, keep open for full-bleed video.
                  Expanded(
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: activeCanvasUrl == null &&
                                artworkSource?.trim().isNotEmpty == true
                            ? Transform.translate(
                                offset: Offset(canvasOffset, 0),
                                child: Opacity(
                                  opacity: canvasDragFraction,
                                  child: Padding(
                                    key: ValueKey('canvas-center-art-${artworkSource ?? visualIdentity}'),
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                    child: Container(
                                      constraints: BoxConstraints(
                                        maxWidth: math.min(constraints.maxWidth * 0.72, 300.0),
                                        maxHeight: math.min(constraints.maxWidth * 0.72, 300.0),
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(24),
                                        boxShadow: [
                                          BoxShadow(
                                            color: (artworkAccentColor ?? effectiveAccent).withValues(alpha: 0.38),
                                            blurRadius: 36,
                                            spreadRadius: 2,
                                            offset: const Offset(0, 12),
                                          ),
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.60),
                                            blurRadius: 20,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(24),
                                        child: AspectRatio(
                                          aspectRatio: 1.0,
                                          child: SourceImage(
                                            source: artworkSource,
                                            fallbackSource: artworkFallbackSource,
                                            fit: BoxFit.cover,
                                            fallback: const SizedBox.shrink(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),

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
                            layoutBuilder: (currentChild, previousChildren) =>
                                Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ...previousChildren,
                                    ?currentChild,
                                  ],
                                ),
                            child: KeyedSubtree(
                              key: ValueKey(
                                'canvas-mini-art-${artworkSource ?? visualIdentity}',
                              ),
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
                                key: const ValueKey(
                                  'player-track-artist-action',
                                ),
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
                          artworkSource: artworkSource,
                          artworkFallbackSource: artworkFallbackSource,
                          accentColor: effectiveAccent,
                          strings: strings,
                        ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Audio quality pill (honors Apariencia -> Mostrar calidad de audio).
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: _PlaybackTimelineQuality(),
                  ),

                  const SizedBox(height: 6),

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
                        activeColor: effectiveAccent,
                        onPressed: hasTrack
                            ? () => player.toggleShuffle()
                            : null,
                      ),
                      IconButton(
                        key: const ValueKey('player-previous-control'),
                        tooltip: strings.previous,
                        color: Colors.white,
                        disabledColor: Colors.white38,
                        iconSize: 38,
                        onPressed: hasTrack
                            ? () => player.playPrevious()
                            : null,
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
                          onPressed: hasTrack
                              ? () => player.togglePlayPause()
                              : null,
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
                        activeColor: effectiveAccent,
                        onPressed: hasTrack
                            ? () => player.cycleRepeatMode()
                            : null,
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
                                    ? effectiveAccent
                                    : Colors.white.withValues(alpha: 0.88),
                              ),
                              if (pairedDeviceName != null) ...[
                                const SizedBox(width: 6),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 150,
                                  ),
                                  child: Text(
                                    pairedDeviceName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: effectiveAccent,
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
                                  ? effectiveAccent
                                  : Colors.white.withValues(alpha: 0.88),
                            ),
                            if (sleepTimer.isActive) ...[
                              const SizedBox(width: 4),
                              Text(
                                '${sleepTimer.remaining.inMinutes + 1}m',
                                style: TextStyle(
                                  color: effectiveAccent,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (shareTrack != null ||
                          (ref.watch(momentClipExportServiceProvider).isSupported &&
                              hasTrack))
                        InutixGuideAnchorTarget(
                          id: InutixGuideAnchors.playerShareMomentId,
                          child: IconButton(
                            key: const ValueKey('spotify-canvas-share-button'),
                            tooltip: strings.shareSong,
                            color: Colors.white.withValues(alpha: 0.88),
                            iconSize: 21,
                            onPressed: () {
                              final momentSupported = ref
                                  .read(momentClipExportServiceProvider)
                                  .isSupported;
                              if (!momentSupported || !hasTrack) {
                                if (shareTrack != null) {
                                  unawaited(
                                    _shareTrack(
                                      context: context,
                                      ref: ref,
                                      track: shareTrack,
                                      strings: strings,
                                    ),
                                  );
                                }
                                return;
                              }
                              unawaited(
                                _showCanvasSharePicker(
                                  context: context,
                                  ref: ref,
                                  strings: strings,
                                  shareTrack: shareTrack,
                                  snapshot: snapshot,
                                  activeCanvasUrl: activeCanvasUrl,
                                  videoStartOffset: videoStartOffset,
                                  artworkSource: artworkSource,
                                  artworkFallbackSource: artworkFallbackSource,
                                  artworkAccentColor: artworkAccentColor,
                                ),
                              );
                            },
                            icon: const Icon(Icons.share_outlined),
                          ),
                        ),
                      IconButton(
                        tooltip: 'Cola de reproducción',
                        onPressed: onToggleQueue,
                        icon: InutilIcon(
                          InutilGlyph.queue,
                          size: 22,
                          filled: queueVisible,
                          color: queueVisible
                              ? effectiveAccent
                              : Colors.white.withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                  ),

                  if (hasError) ...[
                    const SizedBox(height: 6),
                    PlayerErrorMessage(
                      message: errorText ?? strings.playbackError,
                    ),
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
            );
            if (!isWideCanvas) return foreground;
            return Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: foreground,
              ),
            );
          },
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
  const _CanvasFloatingLyricLine({
    required this.onTap,
    this.isDesktop = false,
  });

  final VoidCallback onTap;
  final bool isDesktop;

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
            alignment: isDesktop ? Alignment.center : Alignment.centerLeft,
            child: Text(
              activeText,
              maxLines: 2,
              textAlign: isDesktop ? TextAlign.center : TextAlign.left,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: isDesktop ? 26 : 18,
                fontWeight: FontWeight.w800,
                height: 1.28,
                shadows: const [
                  Shadow(
                    color: Color(0xEE000000),
                    blurRadius: 16,
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

class _CanvasVolumeControl extends ConsumerWidget {
  const _CanvasVolumeControl({required this.volume});

  final double volume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normalizedVolume = volume.clamp(0.0, 1.0);
    return SizedBox(
      width: 140,
      height: 40,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            iconSize: 20 * appVolumeIconScale,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: Icon(
              normalizedVolume <= 0
                  ? Icons.volume_off_rounded
                  : normalizedVolume < 0.5
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded,
              color: Colors.white.withValues(alpha: 0.88),
            ),
            onPressed: () {
              final newVol = normalizedVolume > 0 ? 0.0 : 0.8;
              unawaited(
                ref.read(playerControllerProvider.notifier).setVolume(newVol),
              );
            },
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: normalizedVolume,
                onChanged: (val) {
                  unawaited(
                    ref.read(playerControllerProvider.notifier).setVolume(val),
                  );
                },
              ),
            ),
          ),
        ],
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
    required this.artworkSource,
    required this.artworkFallbackSource,
    required this.accentColor,
    required this.strings,
  });

  final PlayerSnapshot snapshot;
  final bool isFavorite;
  final String? savedTrackId;
  final String? artworkSource;
  final String? artworkFallbackSource;
  final Color accentColor;
  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasIdentity =
        (snapshot.trackId?.trim().isNotEmpty ?? false) ||
        (snapshot.sourceUrl?.trim().isNotEmpty ?? false);
    final catalogPlaylists =
        ref.watch(catalogPlaylistsProvider).value ?? const [];
    final sourceUrl = snapshot.sourceUrl?.trim();
    final remoteTrack =
        snapshot.isRemote && sourceUrl != null && sourceUrl.isNotEmpty
        ? ref
              .read(playerControllerProvider.notifier)
              .currentRemoteTrackFor(sourceUrl)
        : null;
    final savedInLibrary = isSnapshotSavedInLibrary(
      catalogPlaylists: catalogPlaylists,
      snapshot: snapshot,
      isFavorite: isFavorite,
      savedTrackId: savedTrackId,
      remoteTrack: remoteTrack,
    );
    final saveAction =
        ref.watch(
          settingsControllerProvider.select(
            (s) => s.value?.playerSaveButtonAction,
          ),
        ) ??
        PlayerSaveButtonAction.smart;
    final onAccent = accentColor.computeLuminance() > 0.55
        ? Colors.black
        : Colors.white;

    Future<void> openQuickSheet() => showTrackLibraryQuickSheet(
      context: context,
      ref: ref,
      snapshot: snapshot,
      savedTrackId: savedTrackId,
      artworkSource: artworkSource,
      artworkFallbackSource: artworkFallbackSource,
      accentColor: accentColor,
    );

    void handleTap() {
      switch (saveAction) {
        case PlayerSaveButtonAction.picker:
          unawaited(openQuickSheet());
        case PlayerSaveButtonAction.favoritesOnly:
          unawaited(
            _toggleFavoriteForSnapshot(
              context: context,
              ref: ref,
              snapshot: snapshot,
              isFavorite: isFavorite,
              savedTrackId: savedTrackId,
              strings: strings,
            ),
          );
        case PlayerSaveButtonAction.smart:
          if (savedInLibrary) {
            unawaited(openQuickSheet());
          } else {
            unawaited(
              _toggleFavoriteForSnapshot(
                context: context,
                ref: ref,
                snapshot: snapshot,
                isFavorite: isFavorite,
                savedTrackId: savedTrackId,
                strings: strings,
              ),
            );
          }
      }
    }

    return Tooltip(
      message: savedInLibrary
          ? strings.saveToLibraryTitle
          : strings.addToFavorites,
      child: InkWell(
        key: const ValueKey('player-favorite-control'),
        customBorder: const CircleBorder(),
        onTap: hasIdentity ? handleTap : null,
        onLongPress: hasIdentity ? () => unawaited(openQuickSheet()) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: savedInLibrary ? accentColor : Colors.transparent,
            border: Border.all(
              color: savedInLibrary ? accentColor : Colors.white,
              width: 2,
            ),
          ),
          child: Icon(
            savedInLibrary ? Icons.check_rounded : Icons.add_rounded,
            size: 20,
            color: savedInLibrary ? onAccent : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Paint-only breathing color aura layered over the expanded full-bleed album
/// artwork when a song does not have an exact Spotify Canvas / music-video
/// match. Freezes cleanly when playback is paused.
class _CanvasArtworkAmbientAura extends StatefulWidget {
  const _CanvasArtworkAmbientAura({
    required this.accentColor,
    required this.enabled,
    required this.isPlaying,
  });

  final Color accentColor;
  final bool enabled;
  final bool isPlaying;

  @override
  State<_CanvasArtworkAmbientAura> createState() =>
      _CanvasArtworkAmbientAuraState();
}

class _CanvasArtworkAmbientAuraState extends State<_CanvasArtworkAmbientAura>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _CanvasArtworkAmbientAura oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.isPlaying != widget.isPlaying) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.enabled && widget.isPlaying) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop(canceled: false);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const ValueKey('canvas-artwork-ambient-aura'),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final phase = _controller.value * math.pi * 2;
          final dx = math.sin(phase) * 0.42;
          final dy = math.cos(phase * 0.5) * 0.28 - 0.18;
          final pulse = 0.5 + 0.5 * math.sin(phase);
          final glowAlpha = 0.16 + 0.12 * pulse;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(dx, dy),
                radius: 1.05,
                colors: [
                  widget.accentColor.withValues(alpha: glowAlpha),
                  widget.accentColor.withValues(alpha: glowAlpha * 0.25),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.48, 1.0],
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _CanvasShareChoice { moment, song }

Future<void> _showCanvasSharePicker({
  required BuildContext context,
  required WidgetRef ref,
  required AppStrings strings,
  required TrackInfo? shareTrack,
  required PlayerSnapshot snapshot,
  required Uri? activeCanvasUrl,
  required Duration videoStartOffset,
  required String? artworkSource,
  required String? artworkFallbackSource,
  required Color? artworkAccentColor,
}) async {
  final choice = await showPlaybackMenuBottomSheet<_CanvasShareChoice>(
    context: context,
    useRootNavigator: true,
    builder: (menuContext) {
      final foreground = AppColors.menuForegroundFor(menuContext);
      final iconColor = AppColors.menuIconFor(menuContext);
      return SafeArea(
        top: false,
        child: Padding(
          key: const ValueKey('canvas-share-picker-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.shareSong,
                      style: Theme.of(menuContext)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: foreground),
                    ),
                  ),
                  IconButton(
                    tooltip: strings.close,
                    color: foreground,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(menuContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListTile(
                key: const ValueKey('canvas-share-option-moment'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.movie_creation_outlined, color: iconColor),
                title: Text(
                  strings.shareMoment,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  strings.shareMomentSubtitle,
                  style: TextStyle(color: foreground.withValues(alpha: .7)),
                ),
                onTap: () =>
                    Navigator.of(menuContext).pop(_CanvasShareChoice.moment),
              ),
              if (shareTrack != null)
                ListTile(
                  key: const ValueKey('canvas-share-option-song'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.share_rounded, color: iconColor),
                  title: Text(
                    strings.shareSong,
                    style: TextStyle(color: foreground),
                  ),
                  subtitle: Text(
                    strings.shareSongSubtitle,
                    style: TextStyle(color: foreground.withValues(alpha: .7)),
                  ),
                  onTap: () =>
                      Navigator.of(menuContext).pop(_CanvasShareChoice.song),
                ),
            ],
          ),
        ),
      );
    },
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _CanvasShareChoice.moment:
      await _openShareMomentFromPlayer(
        context: context,
        ref: ref,
        snapshot: snapshot,
        videoUri: activeCanvasUrl,
        videoStartOffset: videoStartOffset,
        artworkSource: artworkSource,
        artworkFallbackSource: artworkFallbackSource,
        accentColor: artworkAccentColor,
      );
    case _CanvasShareChoice.song:
      if (shareTrack != null) {
        await _shareTrack(
          context: context,
          ref: ref,
          track: shareTrack,
          strings: strings,
        );
      }
  }
}

/// Subtle translucent banner pills inside the fullscreen player for:
/// 1) Active Listening Room status + live emoji reactions
/// 2) Saved Echo Memory for the currently playing song (dismissible & privacy-gated)
class _PlayerLiveOverlaysBar extends ConsumerStatefulWidget {
  const _PlayerLiveOverlaysBar({
    required this.snapshot,
    required this.spanish,
    required this.accentColor,
  });

  final PlayerSnapshot snapshot;
  final bool spanish;
  final Color accentColor;

  @override
  ConsumerState<_PlayerLiveOverlaysBar> createState() =>
      _PlayerLiveOverlaysBarState();
}

class _PlayerLiveOverlaysBarState
    extends ConsumerState<_PlayerLiveOverlaysBar> {
  String? _dismissedMemoryId;

  @override
  Widget build(BuildContext context) {
    final memory = ref.watch(activeTrackEchoMemoryProvider);
    final bannerAllowed = ref.watch(
      settingsControllerProvider.select(
        (s) => s.asData?.value.echoMemoryBannerEnabled ?? true,
      ),
    );
    final roomService = ref.watch(listeningRoomServiceProvider);
    final activeRoom =
        ref.watch(listeningRoomStateProvider).asData?.value ?? roomService.room;

    final showMemory =
        bannerAllowed &&
        memory != null &&
        memory.showOnPlayback &&
        memory.id != _dismissedMemoryId;

    if (!showMemory && activeRoom == null) {
      return const SizedBox.shrink();
    }

    final latestReaction = roomService.recentBurstReactions.isNotEmpty
        ? roomService.recentBurstReactions.last
        : null;

    return LiveFloatingReactionsOverlay(
      autoListenRoom: true,
      bottomOffset: 50,
      maxTravelHeight: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (activeRoom != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: () => ListeningRoomSheet.show(context),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.48),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color(0xFF1ED760).withValues(alpha: 0.55),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.circle,
                      size: 8,
                      color: Color(0xFF1ED760),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${activeRoom.name} · ${activeRoom.activeMembersAt(DateTime.now()).length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (latestReaction != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${latestReaction.emoji} ${latestReaction.senderName}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        if (showMemory)
          Material(
            color: Colors.black.withValues(alpha: 0.52),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('player-echo-memory-banner'),
              onTap: () => EchoMemoryEditorSheet.show(
                context,
                trackKey: memory.trackKey,
                trackTitle: memory.trackTitle,
                trackArtist: memory.trackArtist,
                trackThumbnailUrl: memory.trackThumbnailUrl,
                existing: memory,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.accentColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_stories_rounded,
                      size: 16,
                      color: widget.accentColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Echo Memory · ${memory.formattedDate(spanish: widget.spanish)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.accentColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            memory.note,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.94),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      onPressed: () =>
                          setState(() => _dismissedMemoryId = memory.id),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
    );
  }
}

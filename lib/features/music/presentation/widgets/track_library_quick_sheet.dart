import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dialog.dart';
import '../../../../services/player/player_service.dart';
import '../../../../services/sharing/inutil_track_link.dart';
import '../../domain/entities/catalog_playlist.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/track_info.dart';
import '../providers/music_providers.dart';
import 'playback_menu_bottom_sheet.dart';
import 'playlist_artwork.dart';
import 'playlist_artwork_mosaic.dart';
import 'playlist_picker_dialog.dart';
import 'source_image.dart';

String? _extractTrackVideoId(PlayerSnapshot snapshot, TrackInfo? remoteTrack) {
  final codec = const InutilTrackLinkCodec();
  if (remoteTrack != null) {
    final id = codec.tryFromTrack(remoteTrack)?.videoId;
    if (id != null && id.isNotEmpty) return id;
  }
  final sourceUrl = snapshot.sourceUrl?.trim();
  if (sourceUrl != null && sourceUrl.isNotEmpty) {
    final uri = Uri.tryParse(sourceUrl);
    final v = uri?.queryParameters['v']?.trim();
    if (v != null && v.length == 11) return v;
  }
  final trackId = snapshot.trackId?.trim();
  if (trackId != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(trackId)) {
    return trackId;
  }
  return null;
}

/// Returns true if the playing track is contained in [catalog] (either as a
/// linked/local track ID or as a remote YouTube video entry).
bool catalogPlaylistContainsSnapshot({
  required CatalogPlaylist catalog,
  required PlayerSnapshot snapshot,
  required String? savedTrackId,
  required String? videoId,
}) {
  final localId = savedTrackId?.trim().isNotEmpty == true
      ? savedTrackId!.trim()
      : (!snapshot.isRemote ? snapshot.trackId?.trim() : null);

  for (final entry in catalog.entries) {
    if (entry.isDeleted) continue;
    if (localId != null &&
        localId.isNotEmpty &&
        entry.localTrackId == localId) {
      return true;
    }
    if (videoId != null &&
        videoId.isNotEmpty &&
        (entry.videoId == videoId || entry.track.key == 'youtube:$videoId')) {
      return true;
    }
  }
  return false;
}

/// Returns true if the playing track is saved in Favorites or any user playlist.
bool isSnapshotSavedInLibrary({
  required List<CatalogPlaylist> catalogPlaylists,
  required PlayerSnapshot snapshot,
  required bool isFavorite,
  required String? savedTrackId,
  TrackInfo? remoteTrack,
}) {
  if (isFavorite) return true;
  final videoId = _extractTrackVideoId(snapshot, remoteTrack);
  for (final catalog in catalogPlaylists) {
    if (catalogPlaylistContainsSnapshot(
      catalog: catalog,
      snapshot: snapshot,
      savedTrackId: savedTrackId,
      videoId: videoId,
    )) {
      return true;
    }
  }
  return false;
}

/// Shows a fast Spotify-style bottom sheet allowing the user to toggle
/// Favorites and add/remove the current song from any playlist (pinning the
/// currently playing playlist right at the top).
Future<void> showTrackLibraryQuickSheet({
  required BuildContext context,
  required WidgetRef ref,
  required PlayerSnapshot snapshot,
  required String? savedTrackId,
  required String? artworkSource,
  required String? artworkFallbackSource,
  required Color accentColor,
}) async {
  await showPlaybackMenuBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _TrackLibraryQuickSheet(
      snapshot: snapshot,
      savedTrackId: savedTrackId,
      artworkSource: artworkSource,
      artworkFallbackSource: artworkFallbackSource,
      accentColor: accentColor,
    ),
  );
}

class _TrackLibraryQuickSheet extends ConsumerStatefulWidget {
  const _TrackLibraryQuickSheet({
    required this.snapshot,
    required this.savedTrackId,
    required this.artworkSource,
    required this.artworkFallbackSource,
    required this.accentColor,
  });

  final PlayerSnapshot snapshot;
  final String? savedTrackId;
  final String? artworkSource;
  final String? artworkFallbackSource;
  final Color accentColor;

  @override
  ConsumerState<_TrackLibraryQuickSheet> createState() =>
      _TrackLibraryQuickSheetState();
}

class _TrackLibraryQuickSheetState
    extends ConsumerState<_TrackLibraryQuickSheet> {
  final Set<String> _busyPlaylistIds = <String>{};

  TrackInfo? _resolveRemoteTrack() {
    final snapshot = widget.snapshot;
    final sourceUrl = snapshot.sourceUrl?.trim();
    if (!snapshot.isRemote || sourceUrl == null || sourceUrl.isEmpty) {
      return null;
    }
    final canonical = ref
        .read(playerControllerProvider.notifier)
        .currentRemoteTrackFor(sourceUrl);
    if (canonical != null) return canonical;
    final strings = ref.read(appStringsProvider);
    return TrackInfo(
      id: snapshot.trackId ?? sourceUrl,
      title: snapshot.title ?? strings.noTitle,
      artist: snapshot.artist ?? strings.unknownArtist,
      url: sourceUrl,
      thumbnailUrl: snapshot.thumbnailUrl,
      duration: snapshot.duration,
      album: snapshot.album,
    );
  }

  Future<void> _toggleFavorites(bool currentlyInFavorites) async {
    if (_busyPlaylistIds.contains(Playlist.favoritesId)) return;
    setState(() => _busyPlaylistIds.add(Playlist.favoritesId));
    try {
      final playlists = ref.read(playlistsControllerProvider.notifier);
      final localId =
          widget.savedTrackId ??
          (!widget.snapshot.isRemote ? widget.snapshot.trackId : null);
      if (localId != null && localId.trim().isNotEmpty) {
        await playlists.toggleFavorite(localId);
      } else {
        final remote = _resolveRemoteTrack();
        if (remote != null) {
          await playlists.toggleFavoriteRemote(remote);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _busyPlaylistIds.remove(Playlist.favoritesId));
      }
    }
  }

  Future<void> _togglePlaylist(
    Playlist playlist, {
    required bool currentlyMember,
  }) async {
    if (_busyPlaylistIds.contains(playlist.id)) return;
    setState(() => _busyPlaylistIds.add(playlist.id));
    try {
      final playlists = ref.read(playlistsControllerProvider.notifier);
      final localId =
          widget.savedTrackId ??
          (!widget.snapshot.isRemote ? widget.snapshot.trackId : null);
      final remote = _resolveRemoteTrack();

      if (currentlyMember) {
        var removed = false;
        if (localId != null && localId.trim().isNotEmpty) {
          final count = await playlists.removeTracksFromPlaylist(playlist.id, [
            localId,
          ]);
          removed = count > 0;
        }
        if (!removed && remote != null) {
          await playlists.removeRemoteTrackFromPlaylist(playlist.id, remote);
        }
      } else {
        if (widget.snapshot.isRemote && remote != null) {
          await playlists.addRemoteTrackToPlaylist(playlist.id, remote);
        } else if (localId != null && localId.trim().isNotEmpty) {
          await playlists.addTrackToPlaylist(playlist.id, localId);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _busyPlaylistIds.remove(playlist.id));
      }
    }
  }

  Future<void> _createNewPlaylistAndAdd() async {
    final strings = ref.read(appStringsProvider);
    final name = await showAppDialog<String>(
      context: context,
      builder: (_) => CreatePlaylistDialog(strings: strings),
    );
    if (!mounted || name == null || name.trim().isEmpty) return;
    try {
      final created = await ref
          .read(playlistsControllerProvider.notifier)
          .create(name.trim());
      if (created != null && mounted) {
        await _togglePlaylist(created, currentlyMember: false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final foreground = AppColors.menuForegroundFor(context);
    final catalogPlaylists =
        ref.watch(catalogPlaylistsProvider).value ?? const <CatalogPlaylist>[];
    final localTracks = ref.watch(libraryTracksProvider).value ?? const [];
    final tracksById = {for (final t in localTracks) t.id: t};
    final activePlaylistId = ref
        .read(playerControllerProvider.notifier)
        .activePlaylistId;

    final remoteTrack = _resolveRemoteTrack();
    final videoId = _extractTrackVideoId(widget.snapshot, remoteTrack);

    CatalogPlaylist? favoritesCatalog;
    final userCatalogs = <CatalogPlaylist>[];
    for (final cat in catalogPlaylists) {
      if (cat.playlist.isFavorites) {
        favoritesCatalog = cat;
      } else {
        userCatalogs.add(cat);
      }
    }

    // Pin the currently playing playlist right at the top (just below Favorites).
    userCatalogs.sort((a, b) {
      final aActive = a.playlist.id == activePlaylistId;
      final bActive = b.playlist.id == activePlaylistId;
      if (aActive != bActive) return aActive ? -1 : 1;
      return b.playlist.updatedAt.compareTo(a.playlist.updatedAt);
    });

    final inFavorites =
        favoritesCatalog != null &&
        catalogPlaylistContainsSnapshot(
          catalog: favoritesCatalog,
          snapshot: widget.snapshot,
          savedTrackId: widget.savedTrackId,
          videoId: videoId,
        );
    final accent = widget.accentColor;
    final onAccent = accent.computeLuminance() > 0.55
        ? Colors.black
        : Colors.white;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Padding(
          key: const ValueKey('track-library-quick-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: cover + song info + "+ Nueva" button.
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: SourceImage(
                        source: widget.artworkSource,
                        fallbackSource: widget.artworkFallbackSource,
                        fit: BoxFit.cover,
                        fallback: const ColoredBox(color: Colors.white12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.saveToLibraryTitle,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Text(
                          widget.snapshot.title ?? strings.noTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground.withValues(alpha: 0.7),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('quick-sheet-new-playlist'),
                    onPressed: _createNewPlaylistAndAdd,
                    icon: Icon(Icons.add_rounded, size: 18, color: accent),
                    label: Text(
                      strings.newPlaylist,
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 6),

              // Scrollable list: Favorites + User playlists.
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _QuickSaveRow(
                      key: const ValueKey('quick-save-favorites'),
                      title: strings.favorites,
                      subtitle: inFavorites
                          ? strings.savedToLibrary
                          : strings.addToFavorites,
                      selected: inFavorites,
                      busy: _busyPlaylistIds.contains(Playlist.favoritesId),
                      accent: accent,
                      onAccent: onAccent,
                      foreground: foreground,
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent,
                              accent.withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                        child: Icon(
                          Icons.favorite_rounded,
                          color: onAccent,
                          size: 22,
                        ),
                      ),
                      onTap: () => unawaited(_toggleFavorites(inFavorites)),
                    ),
                    for (final catalog in userCatalogs)
                      Builder(
                        builder: (context) {
                          final playlist = catalog.playlist;
                          final isMember = catalogPlaylistContainsSnapshot(
                            catalog: catalog,
                            snapshot: widget.snapshot,
                            savedTrackId: widget.savedTrackId,
                            videoId: videoId,
                          );
                          final isCurrent = playlist.id == activePlaylistId;
                          final trackCount = catalog.entries
                              .where((e) => !e.isDeleted)
                              .length;
                          final mosaicSources = playlistArtworkSourcesFor(
                            ref,
                            playlist,
                            () => [
                              for (final entry in catalog.entries.where(
                                (e) => !e.isDeleted,
                              ))
                                if (tracksById[entry.localTrackId]?.thumbnailPath
                                    case final String thumb
                                    when thumb.isNotEmpty)
                                  PlaylistArtworkSource(source: thumb)
                                else if (entry.track.thumbnailUrl
                                    case final String thumb
                                    when thumb.isNotEmpty)
                                  PlaylistArtworkSource(source: thumb),
                            ],
                          );
                          return _QuickSaveRow(
                            key: ValueKey('quick-save-playlist-${playlist.id}'),
                            title: playlist.name,
                            subtitle: strings.songCount(trackCount),
                            badge: isCurrent
                                ? strings.currentPlaylistBadge
                                : null,
                            selected: isMember,
                            busy: _busyPlaylistIds.contains(playlist.id),
                            accent: accent,
                            onAccent: onAccent,
                            foreground: foreground,
                            leading: PlaylistArtworkMosaic(
                              sources: mosaicSources,
                              size: 44,
                            ),
                            onTap: () => unawaited(
                              _togglePlaylist(
                                playlist,
                                currentlyMember: isMember,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                key: const ValueKey('quick-sheet-done'),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  strings.close,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickSaveRow extends StatelessWidget {
  const _QuickSaveRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.busy,
    required this.accent,
    required this.onAccent,
    required this.foreground,
    required this.leading,
    required this.onTap,
    this.badge,
    super.key,
  });

  final String title;
  final String subtitle;
  final String? badge;
  final bool selected;
  final bool busy;
  final Color accent;
  final Color onAccent;
  final Color foreground;
  final Widget leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: leading,
      title: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: accent.withValues(alpha: 0.45)),
              ),
              child: Text(
                badge!,
                style: TextStyle(
                  color: accent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground.withValues(alpha: 0.65),
          fontSize: 12,
        ),
      ),
      trailing: busy
          ? SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: accent),
            )
          : AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? accent : Colors.transparent,
                border: Border.all(
                  color: selected ? accent : foreground.withValues(alpha: 0.45),
                  width: 2,
                ),
              ),
              child: selected
                  ? Icon(Icons.check_rounded, size: 17, color: onAccent)
                  : Icon(
                      Icons.add_rounded,
                      size: 17,
                      color: foreground.withValues(alpha: 0.7),
                    ),
            ),
      onTap: busy ? null : onTap,
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/youtube_music/track_versions_service.dart';
import '../../data/datasources/remote_music_datasource.dart';
import '../providers/music_providers.dart';
import 'source_image.dart';

final trackVersionsServiceProvider = Provider<TrackVersionsService>((ref) {
  final search = ref.watch(youtubeMusicSearchProvider);
  return TrackVersionsService(search: search);
});

final trackVersionsProvider = FutureProvider.autoDispose
    .family<List<TrackVersionCandidate>, TrackVersionLookupRequest>((
      ref,
      request,
    ) {
      return ref.watch(trackVersionsServiceProvider).findVersions(request);
    });

/// Sleek modal sheet that surfaces Original, Live, Acoustic, Remix, Cover, and
/// Remaster versions of the currently playing song.
class TrackVersionsSheet extends ConsumerStatefulWidget {
  const TrackVersionsSheet({
    required this.title,
    required this.artist,
    this.currentVideoId,
    super.key,
  });

  final String title;
  final String artist;
  final String? currentVideoId;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String artist,
    String? currentVideoId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TrackVersionsSheet(
        title: title,
        artist: artist,
        currentVideoId: currentVideoId,
      ),
    );
  }

  @override
  ConsumerState<TrackVersionsSheet> createState() => _TrackVersionsSheetState();
}

class _TrackVersionsSheetState extends ConsumerState<TrackVersionsSheet> {
  TrackVersionKind? _selectedFilter;

  String _formatDuration(Duration? duration) {
    if (duration == null || duration <= Duration.zero) return '';
    final mins = duration.inMinutes;
    final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Color _badgeColor(TrackVersionKind kind, ColorScheme colors) => switch (kind) {
    TrackVersionKind.original => colors.primary,
    TrackVersionKind.live => const Color(0xFFFF6B6B),
    TrackVersionKind.acoustic => const Color(0xFFFFA94D),
    TrackVersionKind.remix => const Color(0xFFCC5DE8),
    TrackVersionKind.cover => const Color(0xFF20C997),
    TrackVersionKind.remaster => const Color(0xFF4DABF7),
    TrackVersionKind.alternate => colors.secondary,
  };

  @override
  Widget build(BuildContext context) {
    final request = TrackVersionLookupRequest(
      title: widget.title,
      artist: widget.artist,
      currentVideoId: widget.currentVideoId,
    );
    final versionsAsync = ref.watch(trackVersionsProvider(request));
    final spanish = ref.watch(appStringsProvider).language != 'en';
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.48,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                child: Row(
                  children: [
                    Icon(Icons.layers_rounded, color: colors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spanish ? 'Otras versiones' : 'Other versions',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${TrackVersionsService.stripVersionQualifiers(widget.title)} · ${widget.artist}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: versionsAsync.when(
                  loading: () => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(
                          spanish
                              ? 'Buscando versiones en vivo, acústicas, remixes...'
                              : 'Finding live, acoustic, remix, and cover versions...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  error: (error, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        spanish
                            ? 'No se pudieron buscar otras versiones en este momento.'
                            : 'Could not search other versions right now.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  data: (items) {
                    if (items.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text(
                            spanish
                                ? 'No encontramos otras versiones verificadas para esta canción.'
                                : 'No other verified versions were found for this song.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    }

                    final availableKinds = <TrackVersionKind>{
                      for (final item in items) item.kind,
                    };
                    final visible = _selectedFilter == null
                        ? items
                        : items
                              .where((item) => item.kind == _selectedFilter)
                              .toList(growable: false);

                    return Column(
                      children: [
                        SizedBox(
                          height: 44,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  selected: _selectedFilter == null,
                                  label: Text(
                                    spanish
                                        ? 'Todas (${items.length})'
                                        : 'All (${items.length})',
                                  ),
                                  onSelected: (_) =>
                                      setState(() => _selectedFilter = null),
                                ),
                              ),
                              for (final kind in TrackVersionKind.values)
                                if (availableKinds.contains(kind))
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      selected: _selectedFilter == kind,
                                      label: Text(kind.label(spanish: spanish)),
                                      onSelected: (_) => setState(
                                        () => _selectedFilter = kind,
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final candidate = visible[index];
                              final song = candidate.song;
                              final badgeColor = _badgeColor(
                                candidate.kind,
                                colors,
                              );
                              final durationText = _formatDuration(
                                song.duration,
                              );
                              return Material(
                                color: colors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () {
                                    final track = trackInfoFromInnerTubeSong(
                                      song,
                                    );
                                    unawaited(
                                      ref
                                          .read(
                                            playerControllerProvider.notifier,
                                          )
                                          .playRemote(track),
                                    );
                                    Navigator.of(context).pop();
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: SizedBox(
                                            width: 52,
                                            height: 52,
                                            child: SourceImage(
                                              source: song.thumbnailUrl,
                                              fit: BoxFit.cover,
                                              fallback: ColoredBox(
                                                color: colors
                                                    .surfaceContainerHighest,
                                                child: const Icon(
                                                  Icons.music_note_rounded,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: badgeColor
                                                          .withValues(
                                                            alpha: 0.16,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            999,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      candidate.isCurrentTrack
                                                          ? (spanish
                                                                ? 'Actual'
                                                                : 'Playing')
                                                          : candidate.kind
                                                                .label(
                                                                  spanish:
                                                                      spanish,
                                                                ),
                                                      style: theme
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            color: badgeColor,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                          ),
                                                    ),
                                                  ),
                                                  if (durationText
                                                      .isNotEmpty) ...[
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      durationText,
                                                      style: theme
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            color: colors
                                                                .onSurfaceVariant,
                                                          ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                song.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                              Text(
                                                song.artists.join(', '),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: colors
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: spanish
                                              ? 'Añadir siguiente a la cola'
                                              : 'Play next',
                                          onPressed: () {
                                            final track =
                                                trackInfoFromInnerTubeSong(
                                                  song,
                                                );
                                            unawaited(
                                              ref
                                                  .read(
                                                    playerControllerProvider
                                                        .notifier,
                                                  )
                                                  .enqueueRemoteNext(track),
                                            );
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  spanish
                                                      ? 'Añadida siguiente a la cola: ${song.title}'
                                                      : 'Added next in queue: ${song.title}',
                                                ),
                                              ),
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.playlist_add_rounded,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

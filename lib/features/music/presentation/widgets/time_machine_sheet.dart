import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/recommendations/time_machine_service.dart';
import '../providers/music_providers.dart';
import 'source_image.dart';

final timeMachineSnapshotProvider =
    FutureProvider.autoDispose<TimeMachineSnapshot>((ref) async {
      final db = ref.watch(databaseServiceProvider);
      final spanish = ref.watch(appStringsProvider).language != 'en';
      final events = await db.getPlaybackEventsForTimeMachine(limit: 10000);
      return TimeMachineAnalyzer.analyze(events, spanish: spanish);
    });

/// Full-height modal experience for "Máquina del Tiempo Musical":
/// - Modo Nostalgia ("Canciones que amabas y olvidaste")
/// - Hace un año / En esta época
/// - Explorar mes a mes con 1 toque para reproducir o guardar como playlist
class TimeMachineSheet extends ConsumerStatefulWidget {
  const TimeMachineSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TimeMachineSheet(),
    );
  }

  @override
  ConsumerState<TimeMachineSheet> createState() => _TimeMachineSheetState();
}

class _TimeMachineSheetState extends ConsumerState<TimeMachineSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _selectedMonthIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _playSession(
    List<TimeMachineTrack> tracks, {
    int startIndex = 0,
  }) async {
    if (tracks.isEmpty) return;
    final player = ref.read(playerControllerProvider.notifier);
    final library = ref.read(libraryTracksProvider).asData?.value ?? const [];
    final localById = {for (final t in library) t.id: t};
    final localBySourceId = {
      for (final t in library)
        if (t.sourceId != null && t.sourceId!.isNotEmpty) t.sourceId!: t,
    };

    final selected = tracks[startIndex.clamp(0, tracks.length - 1)];
    final localHit =
        localById[selected.trackId] ??
        (selected.videoId != null ? localBySourceId[selected.videoId!] : null);

    final playableRemote = tracks
        .map((t) => t.toTrackInfo())
        .where((t) => t.url.isNotEmpty)
        .toList(growable: false);

    if (playableRemote.isNotEmpty) {
      final selectedInfo = selected.toTrackInfo();
      final target = selectedInfo.url.isNotEmpty
          ? selectedInfo
          : playableRemote.first;
      await player.playRemote(target, queue: playableRemote);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    if (localHit != null) {
      await player.playLocal(localHit);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _saveAsPlaylist(
    String name,
    List<TimeMachineTrack> tracks,
  ) async {
    final spanish = ref.read(appStringsProvider).language != 'en';
    final playlistsCtrl = ref.read(playlistsControllerProvider.notifier);
    final created = await playlistsCtrl.create(name);
    if (created == null) return;
    var added = 0;
    for (final item in tracks) {
      final info = item.toTrackInfo();
      if (info.url.isNotEmpty) {
        await playlistsCtrl.addRemoteTrackToPlaylist(created.id, info);
        added += 1;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          spanish
              ? 'Playlist «$name» creada con $added canciones'
              : 'Playlist «$name» created with $added songs',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(timeMachineSnapshotProvider);
    final spanish = ref.watch(appStringsProvider).language != 'en';
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.90,
      minChildSize: 0.58,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, _) {
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
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.history_toggle_off_rounded,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spanish
                                ? 'Máquina del Tiempo'
                                : 'Musical Time Machine',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            spanish
                                ? 'Viaja por tu historial, nostalgia y meses anteriores'
                                : 'Revisit your listening history, nostalgia & past months',
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
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: spanish ? 'Nostalgia' : 'Nostalgia'),
                  Tab(text: spanish ? 'En esta época' : 'On this date'),
                  Tab(text: spanish ? 'Por mes' : 'By month'),
                ],
              ),
              Expanded(
                child: snapshotAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(child: Text('$error')),
                  data: (snapshot) {
                    if (snapshot.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.hourglass_empty_rounded,
                                size: 48,
                                color: colors.onSurfaceVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                spanish
                                    ? 'Tu Máquina del Tiempo está cargando recuerdos'
                                    : 'Your Time Machine is gathering history',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                spanish
                                    ? 'Reproduce canciones en Inutix Music y aquí aparecerán tus sesiones pasadas y temas olvidados.'
                                    : 'Play songs in Inutix Music and your past sessions & forgotten favorites will appear here.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return TabBarView(
                      controller: _tabController,
                      children: [
                        // Tab 1: Modo Nostalgia
                        _TrackCapsuleTab(
                          title: spanish
                              ? 'Canciones que amabas y olvidaste'
                              : 'Songs you loved and forgot',
                          subtitle: spanish
                              ? 'Temas con varias reproducciones que llevan más de 21 días sin sonar.'
                              : 'High-play songs you haven’t heard in over 21 days.',
                          emptyMessage: spanish
                              ? '¡Escuchas todo muy seguido! Cuando dejes descansar algunas favoritas más de 21 días aparecerán aquí.'
                              : 'Everything is fresh! Favorites resting for 21+ days will show up here.',
                          tracks: snapshot.forgottenFavorites,
                          spanish: spanish,
                          showDormantDays: true,
                          onPlayAll: () => unawaited(
                            _playSession(snapshot.forgottenFavorites),
                          ),
                          onPlayIndex: (index) => unawaited(
                            _playSession(
                              snapshot.forgottenFavorites,
                              startIndex: index,
                            ),
                          ),
                          onSavePlaylist: () => unawaited(
                            _saveAsPlaylist(
                              spanish ? 'Modo Nostalgia' : 'Nostalgia Mix',
                              snapshot.forgottenFavorites,
                            ),
                          ),
                        ),

                        // Tab 2: Hace un año / En esta época
                        _TrackCapsuleTab(
                          title: snapshot.onThisDateTitle,
                          subtitle: snapshot.onThisDateSubtitle,
                          emptyMessage: spanish
                              ? 'Aún no hay suficientes datos para esta cápsula.'
                              : 'Not enough data for this capsule yet.',
                          tracks: snapshot.onThisDateTracks,
                          spanish: spanish,
                          showDormantDays: false,
                          onPlayAll: () => unawaited(
                            _playSession(snapshot.onThisDateTracks),
                          ),
                          onPlayIndex: (index) => unawaited(
                            _playSession(
                              snapshot.onThisDateTracks,
                              startIndex: index,
                            ),
                          ),
                          onSavePlaylist: () => unawaited(
                            _saveAsPlaylist(
                              snapshot.onThisDateTitle,
                              snapshot.onThisDateTracks,
                            ),
                          ),
                        ),

                        // Tab 3: Explorar por mes
                        _MonthlyExplorerTab(
                          capsules: snapshot.monthlyCapsules,
                          selectedIndex: _selectedMonthIndex.clamp(
                            0,
                            snapshot.monthlyCapsules.isEmpty
                                ? 0
                                : snapshot.monthlyCapsules.length - 1,
                          ),
                          spanish: spanish,
                          onSelectMonth: (i) =>
                              setState(() => _selectedMonthIndex = i),
                          onPlayAll: (capsule) =>
                              unawaited(_playSession(capsule.tracks)),
                          onPlayIndex: (capsule, idx) => unawaited(
                            _playSession(capsule.tracks, startIndex: idx),
                          ),
                          onSavePlaylist: (capsule) => unawaited(
                            _saveAsPlaylist(
                              capsule.label(spanish: spanish),
                              capsule.tracks,
                            ),
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

class _TrackCapsuleTab extends StatelessWidget {
  const _TrackCapsuleTab({
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    required this.tracks,
    required this.spanish,
    required this.showDormantDays,
    required this.onPlayAll,
    required this.onPlayIndex,
    required this.onSavePlaylist,
  });

  final String title;
  final String subtitle;
  final String emptyMessage;
  final List<TimeMachineTrack> tracks;
  final bool spanish;
  final bool showDormantDays;
  final VoidCallback onPlayAll;
  final ValueChanged<int> onPlayIndex;
  final VoidCallback onSavePlaylist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final now = DateTime.now();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (tracks.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onPlayAll,
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Text(
                          spanish ? 'Reproducir sesión' : 'Play session',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: onSavePlaylist,
                      icon: const Icon(Icons.playlist_add_rounded, size: 18),
                      label: Text(spanish ? 'Playlist' : 'Playlist'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              emptyMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          )
        else
          for (var i = 0; i < tracks.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TimeMachineTrackTile(
                track: tracks[i],
                rank: i + 1,
                subtitleExtra: showDormantDays
                    ? (spanish
                          ? 'Hace ${tracks[i].daysSinceLastPlayed(now)} días · ${tracks[i].playCount}x'
                          : '${tracks[i].daysSinceLastPlayed(now)}d ago · ${tracks[i].playCount}x')
                    : (spanish
                          ? '${tracks[i].playCount} reproducciones'
                          : '${tracks[i].playCount} plays'),
                onTap: () => onPlayIndex(i),
              ),
            ),
      ],
    );
  }
}

class _MonthlyExplorerTab extends StatelessWidget {
  const _MonthlyExplorerTab({
    required this.capsules,
    required this.selectedIndex,
    required this.spanish,
    required this.onSelectMonth,
    required this.onPlayAll,
    required this.onPlayIndex,
    required this.onSavePlaylist,
  });

  final List<TimeMachineMonthCapsule> capsules;
  final int selectedIndex;
  final bool spanish;
  final ValueChanged<int> onSelectMonth;
  final ValueChanged<TimeMachineMonthCapsule> onPlayAll;
  final void Function(TimeMachineMonthCapsule capsule, int index) onPlayIndex;
  final ValueChanged<TimeMachineMonthCapsule> onSavePlaylist;

  @override
  Widget build(BuildContext context) {
    if (capsules.isEmpty) return const SizedBox.shrink();
    final active = capsules[selectedIndex];
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      children: [
        SizedBox(
          height: 50,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            itemCount: capsules.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final capsule = capsules[index];
              return ChoiceChip(
                selected: index == selectedIndex,
                label: Text(capsule.label(spanish: spanish)),
                onSelected: (_) => onSelectMonth(index),
              );
            },
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active.label(spanish: spanish),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        _MiniStatChip(
                          icon: Icons.schedule_rounded,
                          label: '${active.totalMinutes} min',
                        ),
                        _MiniStatChip(
                          icon: Icons.play_circle_outline_rounded,
                          label: spanish
                              ? '${active.totalPlays} reproducciones'
                              : '${active.totalPlays} plays',
                        ),
                        _MiniStatChip(
                          icon: Icons.person_outline_rounded,
                          label: active.topArtist,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => onPlayAll(active),
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 18,
                            ),
                            label: Text(
                              spanish ? 'Reproducir mes' : 'Play month',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => onSavePlaylist(active),
                          icon: const Icon(
                            Icons.playlist_add_rounded,
                            size: 18,
                          ),
                          label: Text(spanish ? 'Playlist' : 'Playlist'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < active.tracks.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TimeMachineTrackTile(
                    track: active.tracks[i],
                    rank: i + 1,
                    subtitleExtra: spanish
                        ? '${active.tracks[i].playCount}x · ${active.tracks[i].totalMinutes} min'
                        : '${active.tracks[i].playCount}x · ${active.tracks[i].totalMinutes} min',
                    onTap: () => onPlayIndex(active, i),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniStatChip extends StatelessWidget {
  const _MiniStatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: colors.primary),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _TimeMachineTrackTile extends StatelessWidget {
  const _TimeMachineTrackTile({
    required this.track,
    required this.rank,
    required this.subtitleExtra,
    required this.onTap,
  });

  final TimeMachineTrack track;
  final int rank;
  final String subtitleExtra;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: SourceImage(
                    source: track.thumbnailUrl,
                    fit: BoxFit.cover,
                    fallback: ColoredBox(
                      color: colors.surfaceContainerHighest,
                      child: const Icon(Icons.music_note_rounded, size: 20),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${track.artist} · $subtitleExtra',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.play_arrow_rounded, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

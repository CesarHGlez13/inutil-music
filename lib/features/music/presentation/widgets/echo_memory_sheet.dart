import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/platform/app_platform.dart';
import '../../../../services/memories/echo_memory.dart';
import '../../../../services/sharing/inutil_track_link.dart';
import '../../domain/entities/track_info.dart';
import '../providers/echo_memory_providers.dart';
import '../providers/music_providers.dart';
import 'source_image.dart';

/// Editor bottom sheet for creating, viewing, or updating an [EchoMemory]
/// attached to a song.
class EchoMemoryEditorSheet extends ConsumerStatefulWidget {
  const EchoMemoryEditorSheet({
    required this.trackKey,
    required this.trackTitle,
    required this.trackArtist,
    this.trackThumbnailUrl,
    this.existing,
    super.key,
  });

  final String trackKey;
  final String trackTitle;
  final String trackArtist;
  final String? trackThumbnailUrl;
  final EchoMemory? existing;

  static Future<EchoMemory?> show(
    BuildContext context, {
    required String trackKey,
    required String trackTitle,
    required String trackArtist,
    String? trackThumbnailUrl,
    EchoMemory? existing,
  }) {
    return showModalBottomSheet<EchoMemory?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EchoMemoryEditorSheet(
        trackKey: trackKey,
        trackTitle: trackTitle,
        trackArtist: trackArtist,
        trackThumbnailUrl: trackThumbnailUrl,
        existing: existing,
      ),
    );
  }

  @override
  ConsumerState<EchoMemoryEditorSheet> createState() =>
      _EchoMemoryEditorSheetState();
}

class _EchoMemoryEditorSheetState extends ConsumerState<EchoMemoryEditorSheet> {
  late final TextEditingController _noteController;
  late DateTime _selectedDate;
  late bool _showOnPlayback;
  File? _pickedPhoto;
  String? _resolvedExistingPhotoPath;
  bool _removeExistingPhoto = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.existing?.note ?? '');
    _selectedDate =
        widget.existing?.memoryDate.toLocal() ?? DateTime.now();
    _showOnPlayback = widget.existing?.showOnPlayback ?? true;
    _loadExistingPhoto();
  }

  Future<void> _loadExistingPhoto() async {
    final fileName = widget.existing?.photoFileName;
    if (fileName == null) return;
    final resolved = await ref
        .read(echoMemoryPhotoServiceProvider)
        .resolve(fileName);
    if (!mounted) return;
    setState(() => _resolvedExistingPhotoPath = resolved);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      File? selected;
      if (AppPlatform.isMobile) {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        if (picked != null) selected = File(picked.path);
      } else {
        final picked = await FilePicker.pickFile(type: FileType.image);
        if (picked?.path != null) selected = File(picked!.path!);
      }
      if (selected != null && mounted) {
        setState(() {
          _pickedPhoto = selected;
          _removeExistingPhoto = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar la foto: $error')),
      );
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
      firstDate: DateTime(1970),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _save() async {
    final note = _noteController.text.trim();
    if (note.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escribe una nota o recuerdo antes de guardar.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(echoMemoryControllerProvider.notifier)
          .saveMemory(
            existingId: widget.existing?.id,
            trackKey: widget.trackKey,
            trackTitle: widget.trackTitle,
            trackArtist: widget.trackArtist,
            trackThumbnailUrl: widget.trackThumbnailUrl,
            note: note,
            memoryDate: _selectedDate,
            newPhotoFile: _pickedPhoto,
            removeExistingPhoto: _removeExistingPhoto,
            existingPhotoFileName: widget.existing?.photoFileName,
            showOnPlayback: _showOnPlayback,
          );
      if (mounted) Navigator.of(context).pop(saved);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar el recuerdo: $error')),
        );
      }
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    setState(() => _saving = true);
    await ref
        .read(echoMemoryControllerProvider.notifier)
        .deleteMemory(existing.id);
    if (mounted) Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final spanish = ref.watch(appStringsProvider).language != 'en';
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final activePhotoPath = _pickedPhoto?.path ??
        (_removeExistingPhoto ? null : _resolvedExistingPhotoPath);
    final tempMemory = EchoMemory(
      id: '',
      trackKey: widget.trackKey,
      titleArtistKey: '',
      trackTitle: widget.trackTitle,
      trackArtist: widget.trackArtist,
      note: '',
      memoryDate: _selectedDate,
      createdAt: _selectedDate,
      updatedAt: _selectedDate,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.auto_stories_rounded,
                      color: colors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Echo Memory',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${widget.trackTitle} · ${widget.trackArtist}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.existing != null)
                    IconButton(
                      tooltip: spanish ? 'Eliminar recuerdo' : 'Delete memory',
                      onPressed: _saving ? null : _delete,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: colors.error,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('echo-memory-note-field'),
                controller: _noteController,
                maxLines: 4,
                minLines: 3,
                maxLength: 320,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: spanish ? 'Tu recuerdo' : 'Your memory',
                  hintText: spanish
                      ? 'Ej. Mi primer viaje a la playa escuchando esto al amanecer...'
                      : 'E.g. Road trip to the beach listening to this at sunrise...',
                  filled: true,
                  fillColor: colors.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('echo-memory-date-btn'),
                      onPressed: _saving ? null : _pickDate,
                      icon: const Icon(Icons.calendar_today_rounded, size: 17),
                      label: Text(tempMemory.formattedDate(spanish: spanish)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('echo-memory-photo-btn'),
                      onPressed: _saving ? null : _pickPhoto,
                      icon: const Icon(Icons.photo_library_rounded, size: 17),
                      label: Text(
                        activePhotoPath == null
                            ? (spanish ? 'Añadir foto' : 'Add photo')
                            : (spanish ? 'Cambiar foto' : 'Change photo'),
                      ),
                    ),
                  ),
                ],
              ),
              if (activePhotoPath != null) ...[
                const SizedBox(height: 12),
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        File(activePhotoPath),
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          onPressed: () => setState(() {
                            _pickedPhoto = null;
                            _removeExistingPhoto = true;
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  spanish
                      ? 'Mostrar recuerdo al reproducir'
                      : 'Show memory during playback',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  spanish
                      ? 'Puedes ocultarlo en privado y abrirlo solo desde el menú.'
                      : 'Turn off to keep it private unless opened manually.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                value: _showOnPlayback,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _showOnPlayback = value),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const ValueKey('echo-memory-save-btn'),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bookmark_added_rounded),
                label: Text(
                  widget.existing == null
                      ? (spanish ? 'Guardar recuerdo' : 'Save memory')
                      : (spanish ? 'Actualizar recuerdo' : 'Update memory'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Timeline gallery sheet listing all saved Echo Memories with 1-tap playback.
class EchoMemoriesGallerySheet extends ConsumerStatefulWidget {
  const EchoMemoriesGallerySheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const EchoMemoriesGallerySheet(),
    );
  }

  @override
  ConsumerState<EchoMemoriesGallerySheet> createState() =>
      _EchoMemoriesGallerySheetState();
}

class _EchoMemoriesGallerySheetState
    extends ConsumerState<EchoMemoriesGallerySheet> {
  String _query = '';

  Future<void> _playMemory(EchoMemory memory) async {
    final player = ref.read(playerControllerProvider.notifier);
    final library = ref.read(libraryTracksProvider).asData?.value ?? const [];
    final localMatch = library.where((track) {
      if (track.id == memory.trackKey || track.sourceId == memory.trackKey) {
        return true;
      }
      return normalizedEchoMemoryTitleArtistKey(track.title, track.artist) ==
          memory.titleArtistKey;
    }).firstOrNull;

    if (localMatch != null) {
      await player.playLocal(localMatch);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    const codec = InutilTrackLinkCodec();
    final videoId = codec.extractVideoId(memory.trackKey);
    if (videoId != null) {
      final track = TrackInfo(
        id: videoId,
        title: memory.trackTitle,
        artist: memory.trackArtist,
        thumbnailUrl: memory.trackThumbnailUrl,
        url: 'https://music.youtube.com/watch?v=$videoId',
      );
      await player.playRemote(track);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final search = ref.read(youtubeMusicSearchProvider);
    final results = await search.searchSongs(
      '${memory.trackTitle} ${memory.trackArtist}',
      limit: 3,
    );
    if (results.isNotEmpty) {
      final top = results.first;
      await player.playRemote(
        TrackInfo(
          id: top.videoId,
          title: top.title,
          artist: top.artists.join(', '),
          thumbnailUrl: top.thumbnailUrl ?? memory.trackThumbnailUrl,
          url: 'https://music.youtube.com/watch?v=${top.videoId}',
          duration: top.duration,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final memoriesAsync = ref.watch(echoMemoryControllerProvider);
    final bannerEnabled =
        ref.watch(settingsControllerProvider).asData?.value.echoMemoryBannerEnabled ??
        true;
    final spanish = ref.watch(appStringsProvider).language != 'en';
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.55,
      maxChildSize: 0.96,
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
                    Icon(Icons.auto_stories_rounded, color: colors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Echo Memory',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            spanish
                                ? 'Tu diario de recuerdos musicales'
                                : 'Your musical memory journal',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: bannerEnabled
                          ? (spanish
                                ? 'Ocultar avisos en reproductor'
                                : 'Hide player banners')
                          : (spanish
                                ? 'Mostrar avisos en reproductor'
                                : 'Show player banners'),
                      onPressed: () => ref
                          .read(settingsControllerProvider.notifier)
                          .setEchoMemoryBannerEnabled(!bannerEnabled),
                      icon: Icon(
                        bannerEnabled
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        color: bannerEnabled
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    hintText: spanish
                        ? 'Buscar por canción, artista o recuerdo...'
                        : 'Search by song, artist, or memory...',
                    filled: true,
                    fillColor: colors.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: memoriesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(child: Text('$error')),
                  data: (memories) {
                    final filtered = _query.isEmpty
                        ? memories
                        : memories
                              .where(
                                (m) =>
                                    m.note.toLowerCase().contains(_query) ||
                                    m.trackTitle.toLowerCase().contains(_query) ||
                                    m.trackArtist.toLowerCase().contains(_query),
                              )
                              .toList(growable: false);

                    if (filtered.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_stories_outlined,
                                size: 48,
                                color: colors.onSurfaceVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                memories.isEmpty
                                    ? (spanish
                                          ? 'Aún no tienes recuerdos guardados'
                                          : 'No saved memories yet')
                                    : (spanish
                                          ? 'Sin resultados para "$_query"'
                                          : 'No matches for "$_query"'),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                spanish
                                    ? 'Abre el menú ⋮ de cualquier canción en el reproductor y toca «Echo Memory» para guardar un momento.'
                                    : 'Open the ⋮ menu of any song in the player and tap «Echo Memory» to save a moment.',
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

                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final memory = filtered[index];
                        return _EchoMemoryCard(
                          memory: memory,
                          spanish: spanish,
                          onPlay: () => unawaited(_playMemory(memory)),
                          onEdit: () => EchoMemoryEditorSheet.show(
                            context,
                            trackKey: memory.trackKey,
                            trackTitle: memory.trackTitle,
                            trackArtist: memory.trackArtist,
                            trackThumbnailUrl: memory.trackThumbnailUrl,
                            existing: memory,
                          ),
                        );
                      },
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

class _EchoMemoryCard extends ConsumerWidget {
  const _EchoMemoryCard({
    required this.memory,
    required this.spanish,
    required this.onPlay,
    required this.onEdit,
  });

  final EchoMemory memory;
  final bool spanish;
  final VoidCallback onPlay;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final photoService = ref.watch(echoMemoryPhotoServiceProvider);

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (memory.photoFileName != null)
            FutureBuilder<String?>(
              future: photoService.resolve(memory.photoFileName),
              builder: (context, snapshot) {
                final path = snapshot.data;
                if (path == null) return const SizedBox.shrink();
                return Image.file(
                  File(path),
                  height: 148,
                  width: double.infinity,
                  fit: BoxFit.cover,
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        memory.formattedDate(spanish: spanish),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (!memory.showOnPlayback) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 14,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: spanish ? 'Editar' : 'Edit',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '“${memory.note}”',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: SourceImage(
                          source: memory.trackThumbnailUrl,
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
                            memory.trackTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            memory.trackArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text(spanish ? 'Escuchar' : 'Play'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

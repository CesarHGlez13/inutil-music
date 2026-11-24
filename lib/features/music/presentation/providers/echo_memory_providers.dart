import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/firebase/firebase_sync_providers.dart';
import '../../../../services/memories/echo_memory.dart';
import '../../../../services/memories/echo_memory_photo_service.dart';
import 'music_providers.dart';

final echoMemoryPhotoServiceProvider = Provider<EchoMemoryPhotoService>(
  (ref) => EchoMemoryPhotoService(),
);

final echoMemoryControllerProvider =
    AsyncNotifierProvider<EchoMemoryController, List<EchoMemory>>(
      EchoMemoryController.new,
    );

/// Resolves the most recent [EchoMemory] matching the currently playing track
/// (by canonical trackKey OR normalized title+artist).
final activeTrackEchoMemoryProvider = Provider<EchoMemory?>((ref) {
  final memories = ref.watch(echoMemoryControllerProvider).asData?.value;
  if (memories == null || memories.isEmpty) return null;
  final player = ref.watch(
    playerControllerProvider.select((state) {
      final snap = state.asData?.value;
      return (
        trackId: snap?.trackId,
        title: snap?.title,
        artist: snap?.artist,
      );
    }),
  );
  if ((player.trackId == null || player.trackId!.trim().isEmpty) &&
      (player.title == null || player.title!.trim().isEmpty)) {
    return null;
  }
  for (final memory in memories) {
    if (memory.matchesTrack(
      trackKey: player.trackId,
      title: player.title,
      artist: player.artist,
    )) {
      return memory;
    }
  }
  return null;
});

class EchoMemoryController extends AsyncNotifier<List<EchoMemory>> {
  static const _uuid = Uuid();

  @override
  Future<List<EchoMemory>> build() async {
    final db = ref.watch(databaseServiceProvider);
    return db.getEchoMemories();
  }

  Future<EchoMemory> saveMemory({
    String? existingId,
    required String trackKey,
    required String trackTitle,
    required String trackArtist,
    String? trackThumbnailUrl,
    required String note,
    required DateTime memoryDate,
    File? newPhotoFile,
    bool removeExistingPhoto = false,
    String? existingPhotoFileName,
    bool showOnPlayback = true,
  }) async {
    final db = ref.read(databaseServiceProvider);
    final photoService = ref.read(echoMemoryPhotoServiceProvider);
    final now = DateTime.now().toUtc();
    final currentList = state.asData?.value ?? await future;
    final previous = existingId == null
        ? null
        : currentList.where((item) => item.id == existingId).firstOrNull;

    String? photoFileName = removeExistingPhoto
        ? null
        : (existingPhotoFileName ?? previous?.photoFileName);
    String? oldPhotoToDelete;

    if (newPhotoFile != null) {
      final savedName = await photoService.saveFile(newPhotoFile);
      oldPhotoToDelete = previous?.photoFileName;
      photoFileName = savedName;
    } else if (removeExistingPhoto && previous?.photoFileName != null) {
      oldPhotoToDelete = previous!.photoFileName;
    }

    final memory = EchoMemory(
      id: existingId ?? _uuid.v4(),
      trackKey: trackKey.trim().isNotEmpty
          ? trackKey.trim()
          : normalizedEchoMemoryTitleArtistKey(trackTitle, trackArtist),
      titleArtistKey: normalizedEchoMemoryTitleArtistKey(
        trackTitle,
        trackArtist,
      ),
      trackTitle: trackTitle.trim().isEmpty ? 'Canción' : trackTitle.trim(),
      trackArtist: trackArtist.trim().isEmpty
          ? 'Inútil Music'
          : trackArtist.trim(),
      trackThumbnailUrl: trackThumbnailUrl?.trim().isNotEmpty == true
          ? trackThumbnailUrl!.trim()
          : previous?.trackThumbnailUrl,
      note: note.trim(),
      memoryDate: memoryDate.toUtc(),
      photoFileName: photoFileName,
      showOnPlayback: showOnPlayback,
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
    );

    await db.upsertEchoMemory(memory);
    if (oldPhotoToDelete != null && oldPhotoToDelete != photoFileName) {
      try {
        await photoService.delete(oldPhotoToDelete);
      } catch (_) {}
    }

    final updated = await db.getEchoMemories();
    state = AsyncData(updated);
    ref.read(inutilCloudBackupProvider).schedulePush();
    return memory;
  }

  Future<void> deleteMemory(String id) async {
    final db = ref.read(databaseServiceProvider);
    final photoService = ref.read(echoMemoryPhotoServiceProvider);
    final currentList = state.asData?.value ?? await future;
    final existing = currentList.where((item) => item.id == id).firstOrNull;
    await db.deleteEchoMemory(id);
    if (existing?.photoFileName != null) {
      try {
        await photoService.delete(existing!.photoFileName);
      } catch (_) {}
    }
    final updated = await db.getEchoMemories();
    state = AsyncData(updated);
    ref.read(inutilCloudBackupProvider).schedulePush();
  }
}

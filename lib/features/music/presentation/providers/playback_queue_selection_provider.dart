import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/firebase/firebase_sync_providers.dart';
import 'music_providers.dart';

/// Playlist rows only need the current occurrence, not the rest of the queue.
final currentQueueLogicalEntryIdProvider = Provider<String?>((ref) {
  final isCurrentDeviceActive = ref.watch(
    inutilPlaybackSyncProvider.select((sync) => sync.isCurrentDeviceActive),
  );
  if (!isCurrentDeviceActive) {
    // En modo control remoto Connect la cola local queda congelada en la pista
    // anterior; las filas de playlist deben coincidir por el `trackId` remoto.
    return null;
  }
  return ref.watch(
    playbackQueueProvider.select((queue) {
      final index = queue.currentIndex;
      return index >= 0 && index < queue.entries.length
          ? queue.entries[index].logicalEntryId
          : null;
    }),
  );
});

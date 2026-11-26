import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/video_preview/video_preview_resolver.dart';
import '../../../../services/youtube_music/innertube_search_service.dart';
import '../../../../services/youtube_music/playback/innertube_playback_service.dart';
import 'music_providers.dart';

final videoPreviewResolverProvider = Provider<VideoPreviewResolver>(
  (ref) {
    final search = ref.watch(youtubeMusicSearchProvider);
    final videoPlayback = InnerTubePlaybackService(
      audioFormatPredicate: (format) => !format.isAudioOnly,
    );
    ref.onDispose(videoPlayback.dispose);
    return VideoPreviewResolver(
      innerTubePlayback: videoPlayback,
      catalog: search is InnerTubeSearchService ? search : null,
    );
  },
);

typedef TrackVideoPreviewRequest = ({String title, String artist, String? videoId});
typedef AlbumVideoPreviewRequest = ({String album, String artist});

final trackVideoPreviewProvider = FutureProvider.autoDispose
    .family<VideoPreviewClip?, TrackVideoPreviewRequest>((ref, request) async {
      final title = request.title.trim();
      final artist = request.artist.trim();
      final videoId = request.videoId?.trim();
      if (title.isEmpty || artist.isEmpty) return null;
      final link = ref.keepAlive();
      final timer = Timer(const Duration(minutes: 5), link.close);
      ref.onDispose(timer.cancel);
      return ref
          .read(videoPreviewResolverProvider)
          .resolveForTrack(title: title, artist: artist, videoId: videoId);
    });

final artistVideoPreviewsProvider = FutureProvider.autoDispose
    .family<List<VideoPreviewClip>, String>((ref, artistName) async {
      final clean = artistName.trim();
      if (clean.isEmpty) return const <VideoPreviewClip>[];
      final link = ref.keepAlive();
      final timer = Timer(const Duration(minutes: 5), link.close);
      ref.onDispose(timer.cancel);
      return ref
          .read(videoPreviewResolverProvider)
          .resolveClipsForArtist(artistName: clean);
    });

final albumVideoPreviewsProvider = FutureProvider.autoDispose
    .family<List<VideoPreviewClip>, AlbumVideoPreviewRequest>((
      ref,
      request,
    ) async {
      final album = request.album.trim();
      final artist = request.artist.trim();
      if (album.isEmpty && artist.isEmpty) return const <VideoPreviewClip>[];
      final link = ref.keepAlive();
      final timer = Timer(const Duration(minutes: 5), link.close);
      ref.onDispose(timer.cancel);
      return ref
          .read(videoPreviewResolverProvider)
          .resolveClipsForAlbum(albumTitle: album, artistName: artist);
    });

import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/features/music/domain/entities/catalog_playlist.dart';
import 'package:inutil_music/features/music/domain/entities/catalog_track.dart';
import 'package:inutil_music/features/music/domain/entities/local_track.dart';
import 'package:inutil_music/features/music/domain/entities/playlist.dart';
import 'package:inutil_music/features/music/domain/entities/playlist_entry.dart';
import 'package:inutil_music/features/music/domain/entities/track_info.dart';
import 'package:inutil_music/features/music/presentation/providers/android_auto_media_browser.dart';
import 'package:inutil_music/features/music/presentation/providers/player/catalog_playback_item.dart';
import 'package:inutil_music/services/youtube_music/innertube_models.dart';

void main() {
  final now = DateTime(2026, 11, 22);

  LocalTrack localTrack(String id, String title, String artist) => LocalTrack(
    id: id,
    title: title,
    artist: artist,
    filePath: '/music/$id.m4a',
    addedAt: now,
    thumbnailUrl: 'https://example.com/$id.jpg',
    duration: const Duration(minutes: 3),
  );

  CatalogPlaylist catalogPlaylist({
    required String id,
    required String name,
    required List<PlaylistEntry> entries,
  }) => CatalogPlaylist(
    playlist: Playlist(
      id: id,
      name: name,
      trackIds: entries.map((e) => e.id).toList(),
      createdAt: now,
      updatedAt: now,
    ),
    entries: entries,
  );

  PlaylistEntry playlistEntry({
    required String entryId,
    required String playlistId,
    required String videoId,
    required String title,
    required String artist,
    int position = 0,
  }) => PlaylistEntry(
    id: entryId,
    playlistId: playlistId,
    remoteVideoId: videoId,
    position: position,
    createdAt: now,
    updatedAt: now,
    track: CatalogTrack.youtube(
      videoId: videoId,
      title: title,
      artists: [artist],
      thumbnailUrl: 'https://example.com/$videoId.jpg',
      duration: const Duration(minutes: 3, seconds: 15),
    ),
  );

  group('AndroidAutoMediaBrowser', () {
    test(
      'exposes four browsable tabs at root and resume item at recent',
      () async {
        final history = [localTrack('h1', 'Cabrón yo puedo', 'Mario Bautista')];
        final browser = AndroidAutoMediaBrowser(
          loadHistory: () async => history,
          loadPlaylists: () async => const [],
          loadCatalogPlaylist: (_) async => null,
          loadLocalTracks: () async => const [],
          searchSongs: (_, {limit = 15}) async => const [],
          playHistoryTrack: (_, {required fallbackQueue}) async {},
          playCatalogPlaylistItem:
              (_, {required queue, required playlistId}) async {},
          playLocalTrack: (_, {required queue}) async {},
          playRemoteTrack: (_, {queue}) async {},
          resumePlayback: () async {},
        );

        final root = await browser.getChildren(
          AndroidAutoMediaBrowser.browsableRootId,
        );
        expect(root.map((item) => item.id).toList(), [
          AndroidAutoMediaBrowser.recentTabId,
          AndroidAutoMediaBrowser.exploreTabId,
          AndroidAutoMediaBrowser.playlistsTabId,
          AndroidAutoMediaBrowser.favoritesTabId,
        ]);
        expect(root.every((item) => !item.playable), isTrue);
        expect(
          root.every(
            (item) =>
                item.thumbnailUrl?.startsWith(
                  'android.resource://com.inutilmusic.app/drawable/ic_aa_tab_',
                ) ==
                true,
          ),
          isTrue,
        );
        expect(root.map((item) => item.title).toList(), [
          'Inicio',
          'Explorar',
          'Playlists',
          'Biblioteca',
        ]);

        final recent = await browser.getChildren(
          AndroidAutoMediaBrowser.recentRootId,
        );
        expect(recent, hasLength(1));
        expect(recent.single.title, 'Cabrón yo puedo');
        expect(recent.single.playable, isTrue);
      },
    );

    test(
      'builds Spotify-style grouped Inicio sections and resolves HD playlist covers',
      () async {
        const googleThumb120 =
            'https://lh3.googleusercontent.com/abc123=w120-h120-l90-rj';
        const googleThumb640 =
            'https://lh3.googleusercontent.com/abc123=w640-h640-l90-rj';
        final history = [localTrack('h1', 'Cabrón yo puedo', 'Mario Bautista')];
        final miasPlaylist = catalogPlaylist(
          id: 'pl-mias',
          name: 'Mias',
          entries: [
            PlaylistEntry(
              id: 'e1',
              playlistId: 'pl-mias',
              remoteVideoId: 'vid1',
              position: 0,
              createdAt: now,
              updatedAt: now,
              track: CatalogTrack.youtube(
                videoId: 'vid1',
                title: 'Because Of You',
                artists: const ['LIZOT'],
                thumbnailUrl: googleThumb120,
              ),
            ),
          ],
        );

        final browser = AndroidAutoMediaBrowser(
          loadHistory: () async => history,
          loadPlaylists: () async => [miasPlaylist.playlist],
          loadCatalogPlaylist: (id) async =>
              id == 'pl-mias' ? miasPlaylist : null,
          loadLocalTracks: () async => const [],
          searchSongs: (_, {limit = 15}) async => const [],
          playHistoryTrack: (_, {required fallbackQueue}) async {},
          playCatalogPlaylistItem:
              (_, {required queue, required playlistId}) async {},
          playLocalTrack: (_, {required queue}) async {},
          playRemoteTrack: (_, {queue}) async {},
          resumePlayback: () async {},
        );

        final home = await browser.getChildren(
          AndroidAutoMediaBrowser.recentTabId,
        );
        expect(home, hasLength(2));
        expect(
          home[0].extras?[AndroidAutoMediaBrowser
              .contentStyleGroupTitleHintKey],
          'Escuchado recientemente',
        );
        expect(home[1].title, 'Mias');
        expect(home[1].thumbnailUrl, googleThumb640);
        expect(
          home[1].extras?[AndroidAutoMediaBrowser
              .contentStyleGroupTitleHintKey],
          'Tus playlists',
        );
      },
    );

    test(
      'browses playlists and favorites and plays selected item with full queue',
      () async {
        final miasPlaylist = catalogPlaylist(
          id: 'pl-mias',
          name: 'Mias',
          entries: [
            playlistEntry(
              entryId: 'e1',
              playlistId: 'pl-mias',
              videoId: 'vid1',
              title: 'Because Of You',
              artist: 'LIZOT',
              position: 0,
            ),
            playlistEntry(
              entryId: 'e2',
              playlistId: 'pl-mias',
              videoId: 'vid2',
              title: 'Unstoppable',
              artist: 'Sia',
              position: 1,
            ),
          ],
        );
        final favoritesPlaylist = catalogPlaylist(
          id: Playlist.favoritesId,
          name: 'Favoritos',
          entries: [
            playlistEntry(
              entryId: 'fav1',
              playlistId: Playlist.favoritesId,
              videoId: 'vidFav',
              title: 'Te Veo a la Vuelta',
              artist: 'José Madero',
            ),
          ],
        );

        CatalogPlaybackItem? playedItem;
        List<CatalogPlaybackItem>? playedQueue;
        String? playedPlaylistId;

        final browser = AndroidAutoMediaBrowser(
          loadHistory: () async => const [],
          loadPlaylists: () async => [
            favoritesPlaylist.playlist,
            miasPlaylist.playlist,
          ],
          loadCatalogPlaylist: (id) async {
            if (id == 'pl-mias') return miasPlaylist;
            if (id == Playlist.favoritesId) return favoritesPlaylist;
            return null;
          },
          loadLocalTracks: () async => const [],
          searchSongs: (_, {limit = 15}) async => const [],
          playHistoryTrack: (_, {required fallbackQueue}) async {},
          playCatalogPlaylistItem:
              (selected, {required queue, required playlistId}) async {
                playedItem = selected;
                playedQueue = queue;
                playedPlaylistId = playlistId;
              },
          playLocalTrack: (_, {required queue}) async {},
          playRemoteTrack: (_, {queue}) async {},
          resumePlayback: () async {},
        );

        final playlists = await browser.getChildren(
          AndroidAutoMediaBrowser.playlistsTabId,
        );
        expect(playlists, hasLength(1));
        expect(playlists.single.title, 'Mias');
        expect(playlists.single.playable, isFalse);

        final miasItems = await browser.getChildren(playlists.single.id);
        expect(miasItems.map((e) => e.title), [
          'Because Of You',
          'Unstoppable',
        ]);
        await browser.playFromMediaId(miasItems[1].id);
        expect(playedPlaylistId, 'pl-mias');
        expect(playedItem?.entryId, 'e2');
        expect(playedQueue, hasLength(2));

        final favItems = await browser.getChildren(
          AndroidAutoMediaBrowser.favoritesTabId,
        );
        expect(favItems, hasLength(1));
        await browser.playFromMediaId(favItems.single.id);
        expect(playedPlaylistId, Playlist.favoritesId);
        expect(playedItem?.entryId, 'fav1');
      },
    );

    test(
      'supports remote voice search, offline local fallback, and empty query resume',
      () async {
        final locals = [localTrack('loc1', 'Me Toco Perder', 'Victor Eme')];
        TrackInfo? playedRemote;
        LocalTrack? playedLocal;
        var resumed = false;
        var failRemoteSearch = false;

        final browser = AndroidAutoMediaBrowser(
          loadHistory: () async => const [],
          loadPlaylists: () async => const [],
          loadCatalogPlaylist: (_) async => null,
          loadLocalTracks: () async => locals,
          searchSongs: (query, {limit = 15}) async {
            if (failRemoteSearch) {
              throw Exception('offline');
            }
            return [
              InnerTubeSong(
                videoId: 'yt123',
                title: 'Ella Está Triste',
                artists: const ['Grupo Historia'],
                thumbnailUrl: 'https://example.com/yt123.jpg',
              ),
            ];
          },
          playHistoryTrack: (_, {required fallbackQueue}) async {},
          playCatalogPlaylistItem:
              (_, {required queue, required playlistId}) async {},
          playLocalTrack: (track, {required queue}) async {
            playedLocal = track;
          },
          playRemoteTrack: (track, {queue}) async {
            playedRemote = track;
          },
          resumePlayback: () async {
            resumed = true;
          },
          hasActiveTrack: () => true,
        );

        await browser.playFromSearch('Ella Está Triste');
        expect(playedRemote?.id, 'yt123');
        expect(playedRemote?.title, 'Ella Está Triste');

        failRemoteSearch = true;
        await browser.playFromSearch('Victor Eme');
        expect(playedLocal?.id, 'loc1');

        await browser.playFromSearch('');
        expect(resumed, isTrue);
      },
    );

    test(
      'exposes personalized Home recommendations, recommended playlists, and Explorar categories',
      () async {
        TrackInfo? playedRemote;
        List<TrackInfo>? playedQueue;

        final recTrack = TrackInfo(
          id: 'vidThunder',
          title: 'Thunder',
          artist: 'Gabry Ponte, LUM!X',
          url: 'https://www.youtube.com/watch?v=vidThunder',
          thumbnailUrl:
              'https://lh3.googleusercontent.com/thunder=w120-h120-l90-rj',
        );
        final mixTrack = TrackInfo(
          id: 'vidMix1',
          title: 'Clásico Tranquilo',
          artist: 'Lewis Capaldi',
          url: 'https://www.youtube.com/watch?v=vidMix1',
          thumbnailUrl: 'https://example.com/mix1.jpg',
        );

        final browser = AndroidAutoMediaBrowser(
          loadHistory: () async => const [],
          loadPlaylists: () async => const [],
          loadCatalogPlaylist: (_) async => null,
          loadLocalTracks: () async => const [],
          searchSongs: (_, {limit = 15}) async => const [],
          loadHomeSections: () async => [
            AndroidAutoHomeSection(
              title: 'Porque escuchaste Self Aware',
              items: [AndroidAutoHomeTrack(recTrack)],
            ),
            const AndroidAutoHomeSection(
              title: 'Melodías relajantes',
              items: [
                AndroidAutoHomeCollection(
                  title: 'Clásicos de Pop Tranquilo',
                  browseId: 'VLPL_RELAX',
                  subtitle: 'Mix recomendado',
                  thumbnailUrl: 'https://example.com/relax.jpg',
                ),
              ],
            ),
          ],
          loadCollectionTracks: (browseId) async =>
              browseId == 'VLPL_RELAX' ? [mixTrack] : const [],
          loadExploreCategories: () async => const [
            AndroidAutoExploreCategory(
              id: 'mood_fiesta',
              title: 'Fiesta',
              searchQuery: 'musica de fiesta',
              artworkUrl: 'https://example.com/fiesta.jpg',
            ),
          ],
          loadExploreCategoryPage: (_) async =>
              AndroidAutoExplorePage(tracks: [recTrack]),
          playHistoryTrack: (_, {required fallbackQueue}) async {},
          playCatalogPlaylistItem:
              (_, {required queue, required playlistId}) async {},
          playLocalTrack: (_, {required queue}) async {},
          playRemoteTrack: (track, {queue}) async {
            playedRemote = track;
            playedQueue = queue;
          },
          resumePlayback: () async {},
        );

        final home = await browser.getChildren(
          AndroidAutoMediaBrowser.recentTabId,
        );
        expect(home, hasLength(2));
        expect(home[0].title, 'Thunder');
        expect(
          home[0].extras?[AndroidAutoMediaBrowser
              .contentStyleGroupTitleHintKey],
          'Porque escuchaste Self Aware',
        );
        expect(
          home[0].thumbnailUrl,
          'https://lh3.googleusercontent.com/thunder=w640-h640-l90-rj',
        );

        await browser.playFromMediaId(home[0].id);
        expect(playedRemote?.id, 'vidThunder');
        expect(playedQueue, hasLength(1));

        expect(home[1].title, 'Clásicos de Pop Tranquilo');
        expect(home[1].playable, isFalse);
        final mixItems = await browser.getChildren(home[1].id);
        expect(mixItems, hasLength(1));
        await browser.playFromMediaId(mixItems.single.id);
        expect(playedRemote?.id, 'vidMix1');

        final explore = await browser.getChildren(
          AndroidAutoMediaBrowser.exploreTabId,
        );
        expect(explore, hasLength(1));
        expect(explore.single.title, 'Fiesta');
        final fiestaItems = await browser.getChildren(explore.single.id);
        expect(fiestaItems, hasLength(1));
        expect(fiestaItems.single.title, 'Thunder');
      },
    );
  });
}

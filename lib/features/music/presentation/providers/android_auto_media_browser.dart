import '../../../../core/utils/image_source.dart';
import '../../../../services/media_session/desktop_media_session.dart';
import '../../../../services/youtube_music/innertube_models.dart';
import '../../data/datasources/remote_music_datasource.dart';
import '../../domain/entities/catalog_playlist.dart';
import '../../domain/entities/local_track.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/track_info.dart';
import 'player/catalog_playback_item.dart';
import 'player/catalog_playlist_playback.dart';

/// A single item inside a personalized Android Auto Home section.
sealed class AndroidAutoHomeItem {
  const AndroidAutoHomeItem();
}

final class AndroidAutoHomeTrack extends AndroidAutoHomeItem {
  const AndroidAutoHomeTrack(this.track);

  final TrackInfo track;
}

final class AndroidAutoHomeCollection extends AndroidAutoHomeItem {
  const AndroidAutoHomeCollection({
    required this.title,
    required this.browseId,
    this.subtitle,
    this.thumbnailUrl,
  });

  final String title;
  final String browseId;
  final String? subtitle;
  final String? thumbnailUrl;
}

final class AndroidAutoHomeArtist extends AndroidAutoHomeItem {
  const AndroidAutoHomeArtist({required this.name, this.thumbnailUrl});

  final String name;
  final String? thumbnailUrl;
}

/// One grouped section on Android Auto's Inicio tab (e.g. *Seguir escuchando*,
/// *Porque escuchaste...*, *Nuevos para ti*, *Descubrimiento*, *Mixes*).
class AndroidAutoHomeSection {
  const AndroidAutoHomeSection({required this.title, required this.items});

  final String title;
  final List<AndroidAutoHomeItem> items;
}

/// One mood/genre category exposed under Android Auto's Explorar tab.
class AndroidAutoExploreCategory {
  const AndroidAutoExploreCategory({
    required this.id,
    required this.title,
    required this.searchQuery,
    this.artworkUrl,
  });

  final String id;
  final String title;
  final String searchQuery;
  final String? artworkUrl;
}

/// Resolved content inside an Explorar mood/genre category.
class AndroidAutoExplorePage {
  const AndroidAutoExplorePage({
    this.collections = const <AndroidAutoHomeCollection>[],
    this.tracks = const <TrackInfo>[],
  });

  final List<AndroidAutoHomeCollection> collections;
  final List<TrackInfo> tracks;
}

/// Builds a Spotify-parity Android Auto browse hierarchy mirroring Inútil
/// Music's real personalized feed:
/// - **Inicio**: personalized recommendation sections (*Seguir escuchando*,
///   *Porque escuchaste...*, *Nuevos para ti*, *Descubrimiento*, *Mixes*,
///   *Artistas recomendados*) plus *Tus playlists*, rendered as crisp 640×640
///   square grid cards.
/// - **Explorar**: moods & genres (*Concentración*, *Ejercicio*, *Energía*,
///   *Fiesta*, *Dormir*, *Gaming*...) with browsable playlists and tracks.
/// - **Playlists**: your saved playlists as square HD cover grid cards.
/// - **Biblioteca**: grouped *Favoritos* and offline *Descargadas* sections.
class AndroidAutoMediaBrowser {
  AndroidAutoMediaBrowser({
    required this.loadHistory,
    required this.loadPlaylists,
    required this.loadCatalogPlaylist,
    required this.loadLocalTracks,
    required this.searchSongs,
    required this.playHistoryTrack,
    required this.playCatalogPlaylistItem,
    required this.playLocalTrack,
    required this.playRemoteTrack,
    required this.resumePlayback,
    this.loadHomeSections,
    this.loadCollectionTracks,
    this.loadExploreCategories,
    this.loadExploreCategoryPage,
    this.hasActiveTrack,
    this.resolveCustomPlaylistArtworkPath,
  });

  static const browsableRootId = 'root';
  static const recentRootId = 'recent';
  static const recentTabId = 'auto:tab:recent';
  static const exploreTabId = 'auto:tab:explore';
  static const playlistsTabId = 'auto:tab:playlists';
  static const favoritesTabId = 'auto:tab:favorites';
  static const downloadsTabId = 'auto:tab:downloads';

  static const contentStyleGroupTitleHintKey =
      'android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT';
  static const contentStyleBrowsableHintKey =
      'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT';
  static const contentStylePlayableHintKey =
      'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT';
  static const contentStyleListValue = 1;
  static const contentStyleGridValue = 2;

  static const _tabIconHome =
      'android.resource://com.inutilmusic.app/drawable/ic_aa_tab_home';
  static const _tabIconExplore =
      'android.resource://com.inutilmusic.app/drawable/ic_aa_tab_explore';
  static const _tabIconPlaylists =
      'android.resource://com.inutilmusic.app/drawable/ic_aa_tab_playlists';
  static const _tabIconFavorites =
      'android.resource://com.inutilmusic.app/drawable/ic_aa_tab_favorites';

  static const _playlistPrefix = 'auto:playlist|';
  static const _playlistItemPrefix = 'auto:playlist_item|';
  static const _historyPrefix = 'auto:history|';
  static const _localPrefix = 'auto:local|';
  static const _searchPrefix = 'auto:search|';
  static const _recTrackPrefix = 'auto:rec_track|';
  static const _recCollectionPrefix = 'auto:rec_collection|';
  static const _recCollectionTrackPrefix = 'auto:rec_collection_track|';
  static const _recArtistPrefix = 'auto:rec_artist|';
  static const _exploreCategoryPrefix = 'auto:explore|';
  static const _exploreTrackPrefix = 'auto:explore_track|';

  final Future<List<LocalTrack>> Function() loadHistory;
  final Future<List<Playlist>> Function() loadPlaylists;
  final Future<CatalogPlaylist?> Function(String playlistId)
  loadCatalogPlaylist;
  final Future<List<LocalTrack>> Function() loadLocalTracks;
  final Future<List<InnerTubeSong>> Function(String query, {int limit})
  searchSongs;
  final Future<void> Function(
    LocalTrack track, {
    required List<LocalTrack> fallbackQueue,
  })
  playHistoryTrack;
  final Future<void> Function(
    CatalogPlaybackItem selected, {
    required List<CatalogPlaybackItem> queue,
    required String playlistId,
  })
  playCatalogPlaylistItem;
  final Future<void> Function(
    LocalTrack track, {
    required List<LocalTrack> queue,
  })
  playLocalTrack;
  final Future<void> Function(TrackInfo track, {List<TrackInfo>? queue})
  playRemoteTrack;
  final Future<void> Function() resumePlayback;
  final Future<List<AndroidAutoHomeSection>> Function()? loadHomeSections;
  final Future<List<TrackInfo>> Function(String browseId)? loadCollectionTracks;
  final Future<List<AndroidAutoExploreCategory>> Function()?
  loadExploreCategories;
  final Future<AndroidAutoExplorePage> Function(
    AndroidAutoExploreCategory category,
  )?
  loadExploreCategoryPage;
  final bool Function()? hasActiveTrack;
  final Future<String?> Function(String customArtworkFileName)?
  resolveCustomPlaylistArtworkPath;

  final Map<String, TrackInfo> _cachedSearchTracks = <String, TrackInfo>{};
  List<TrackInfo> _lastSearchQueue = const <TrackInfo>[];
  final Map<String, List<TrackInfo>> _cachedRecSectionQueues =
      <String, List<TrackInfo>>{};
  final Map<String, List<TrackInfo>> _cachedCollectionQueues =
      <String, List<TrackInfo>>{};
  final Map<String, AndroidAutoExploreCategory> _cachedExploreCategories =
      <String, AndroidAutoExploreCategory>{};
  final Map<String, List<TrackInfo>> _cachedExploreTrackQueues =
      <String, List<TrackInfo>>{};

  Future<List<DesktopMediaBrowseItem>> getChildren(String parentMediaId) async {
    switch (parentMediaId) {
      case browsableRootId:
        return const <DesktopMediaBrowseItem>[
          DesktopMediaBrowseItem(
            id: recentTabId,
            title: 'Inicio',
            subtitle: 'Recomendaciones y tus listas',
            thumbnailUrl: _tabIconHome,
            playable: false,
            extras: <String, dynamic>{
              contentStyleBrowsableHintKey: contentStyleGridValue,
              contentStylePlayableHintKey: contentStyleGridValue,
            },
          ),
          DesktopMediaBrowseItem(
            id: exploreTabId,
            title: 'Explorar',
            subtitle: 'Estados de ánimo y géneros',
            thumbnailUrl: _tabIconExplore,
            playable: false,
            extras: <String, dynamic>{
              contentStyleBrowsableHintKey: contentStyleGridValue,
              contentStylePlayableHintKey: contentStyleListValue,
            },
          ),
          DesktopMediaBrowseItem(
            id: playlistsTabId,
            title: 'Playlists',
            subtitle: 'Tus listas guardadas',
            thumbnailUrl: _tabIconPlaylists,
            playable: false,
            extras: <String, dynamic>{
              contentStyleBrowsableHintKey: contentStyleGridValue,
              contentStylePlayableHintKey: contentStyleListValue,
            },
          ),
          DesktopMediaBrowseItem(
            id: favoritesTabId,
            title: 'Biblioteca',
            subtitle: 'Favoritos y descargadas',
            thumbnailUrl: _tabIconFavorites,
            playable: false,
            extras: <String, dynamic>{
              contentStylePlayableHintKey: contentStyleListValue,
            },
          ),
        ];
      case recentRootId:
        final history = await loadHistory();
        if (history.isEmpty) {
          return const <DesktopMediaBrowseItem>[];
        }
        return <DesktopMediaBrowseItem>[_historyBrowseItem(history.first)];
      case recentTabId:
        return _homeSections();
      case exploreTabId:
        return _exploreGridCards();
      case playlistsTabId:
        return _playlistGridCards();
      case favoritesTabId:
        return _librarySections();
      case downloadsTabId:
        return _downloadedLocalItems();
      default:
        if (parentMediaId.startsWith(_playlistPrefix)) {
          final encodedId = parentMediaId.substring(_playlistPrefix.length);
          final playlistId = Uri.decodeComponent(encodedId);
          return _playlistChildren(playlistId);
        }
        if (parentMediaId.startsWith(_recCollectionPrefix)) {
          final browseId = Uri.decodeComponent(
            parentMediaId.substring(_recCollectionPrefix.length),
          );
          return _collectionChildren(browseId);
        }
        if (parentMediaId.startsWith(_recArtistPrefix)) {
          final artistName = Uri.decodeComponent(
            parentMediaId.substring(_recArtistPrefix.length),
          );
          return search(artistName);
        }
        if (parentMediaId.startsWith(_exploreCategoryPrefix)) {
          final categoryId = Uri.decodeComponent(
            parentMediaId.substring(_exploreCategoryPrefix.length),
          );
          return _exploreCategoryChildren(categoryId);
        }
        return const <DesktopMediaBrowseItem>[];
    }
  }

  Future<void> playFromMediaId(String mediaId) async {
    if (mediaId.startsWith(_historyPrefix)) {
      final trackId = Uri.decodeComponent(
        mediaId.substring(_historyPrefix.length),
      );
      final history = await loadHistory();
      final selected = _findLocalById(history, trackId);
      if (selected != null) {
        await playHistoryTrack(selected, fallbackQueue: history);
      }
      return;
    }

    if (mediaId.startsWith(_localPrefix)) {
      final trackId = Uri.decodeComponent(
        mediaId.substring(_localPrefix.length),
      );
      final localTracks = await _downloadedLocalTracks();
      final selected = _findLocalById(localTracks, trackId);
      if (selected != null) {
        await playLocalTrack(selected, queue: localTracks);
      }
      return;
    }

    if (mediaId.startsWith(_playlistItemPrefix)) {
      final parts = mediaId.substring(_playlistItemPrefix.length).split('|');
      if (parts.length < 2) {
        return;
      }
      final playlistId = Uri.decodeComponent(parts[0]);
      final entryId = Uri.decodeComponent(parts[1]);
      final catalog = await loadCatalogPlaylist(playlistId);
      if (catalog == null) {
        return;
      }
      final localTracks = await loadLocalTracks();
      final items = catalogPlaylistPlaybackItems(catalog, localTracks);
      for (final item in items) {
        if (item.entryId == entryId) {
          await playCatalogPlaylistItem(
            item,
            queue: items,
            playlistId: playlistId,
          );
          return;
        }
      }
      return;
    }

    if (mediaId.startsWith(_recTrackPrefix)) {
      final parts = mediaId.substring(_recTrackPrefix.length).split('|');
      if (parts.length < 2) {
        return;
      }
      final sectionKey = Uri.decodeComponent(parts[0]);
      final videoId = Uri.decodeComponent(parts[1]);
      final queue = _cachedRecSectionQueues[sectionKey];
      final selected = _findRemoteById(queue, videoId);
      if (selected != null) {
        await playRemoteTrack(selected, queue: queue);
        return;
      }
      await playRemoteTrack(_fallbackRemoteTrack(videoId));
      return;
    }

    if (mediaId.startsWith(_recCollectionTrackPrefix)) {
      final parts = mediaId
          .substring(_recCollectionTrackPrefix.length)
          .split('|');
      if (parts.length < 2) {
        return;
      }
      final browseId = Uri.decodeComponent(parts[0]);
      final videoId = Uri.decodeComponent(parts[1]);
      var queue = _cachedCollectionQueues[browseId];
      if ((queue == null || queue.isEmpty) && loadCollectionTracks != null) {
        try {
          queue = await loadCollectionTracks!(browseId);
          _cachedCollectionQueues[browseId] = queue;
        } catch (_) {
          queue = null;
        }
      }
      final selected = _findRemoteById(queue, videoId);
      if (selected != null) {
        await playRemoteTrack(selected, queue: queue);
        return;
      }
      await playRemoteTrack(_fallbackRemoteTrack(videoId));
      return;
    }

    if (mediaId.startsWith(_exploreTrackPrefix)) {
      final parts = mediaId.substring(_exploreTrackPrefix.length).split('|');
      if (parts.length < 2) {
        return;
      }
      final categoryId = Uri.decodeComponent(parts[0]);
      final videoId = Uri.decodeComponent(parts[1]);
      final queue = _cachedExploreTrackQueues[categoryId];
      final selected = _findRemoteById(queue, videoId);
      if (selected != null) {
        await playRemoteTrack(selected, queue: queue);
        return;
      }
      await playRemoteTrack(_fallbackRemoteTrack(videoId));
      return;
    }

    if (mediaId.startsWith(_searchPrefix)) {
      final videoId = Uri.decodeComponent(
        mediaId.substring(_searchPrefix.length),
      );
      final cached = _cachedSearchTracks[videoId];
      if (cached != null) {
        await playRemoteTrack(
          cached,
          queue: _lastSearchQueue.isEmpty ? null : _lastSearchQueue,
        );
        return;
      }
      await playRemoteTrack(_fallbackRemoteTrack(videoId));
    }
  }

  Future<List<DesktopMediaBrowseItem>> search(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return getChildren(recentTabId);
    }
    try {
      final songs = await searchSongs(normalized, limit: 15);
      if (songs.isNotEmpty) {
        final tracks = songs
            .map(trackInfoFromInnerTubeSong)
            .toList(growable: false);
        _lastSearchQueue = tracks;
        for (final track in tracks) {
          _cachedSearchTracks[track.id] = track;
        }
        return tracks
            .map(
              (track) => DesktopMediaBrowseItem(
                id: '$_searchPrefix${Uri.encodeComponent(track.id)}',
                title: track.title,
                subtitle: track.artist.isEmpty ? 'Inútil Music' : track.artist,
                album: track.album,
                thumbnailUrl: _highResArtwork(track.thumbnailUrl),
                duration: track.duration,
                playable: true,
              ),
            )
            .toList(growable: false);
      }
    } catch (_) {
      // Offline fallback to local library below.
    }

    final localTracks = await _downloadedLocalTracks();
    final lower = normalized.toLowerCase();
    return localTracks
        .where(
          (track) =>
              track.title.toLowerCase().contains(lower) ||
              track.artist.toLowerCase().contains(lower),
        )
        .take(20)
        .map(_localBrowseItem)
        .toList(growable: false);
  }

  Future<void> playFromSearch(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      if (hasActiveTrack?.call() == true) {
        await resumePlayback();
        return;
      }
      final history = await loadHistory();
      if (history.isNotEmpty) {
        await playHistoryTrack(history.first, fallbackQueue: history);
        return;
      }
      final localTracks = await _downloadedLocalTracks();
      if (localTracks.isNotEmpty) {
        await playLocalTrack(localTracks.first, queue: localTracks);
      }
      return;
    }

    final results = await search(normalized);
    if (results.isNotEmpty) {
      await playFromMediaId(results.first.id);
    }
  }

  /// Spotify-style personalized Inicio tab matching Inútil Music mobile:
  /// live recommendation sections (*Seguir escuchando*, *Porque escuchaste...*,
  /// *Nuevos para ti*, *Descubrimiento*, *Melodías relajantes / Mixes*,
  /// *Artistas recomendados*) plus *Tus playlists*, with automatic offline
  /// fallback to local history and saved playlists.
  Future<List<DesktopMediaBrowseItem>> _homeSections() async {
    final homeSectionsFuture = loadHomeSections == null
        ? Future<List<AndroidAutoHomeSection>>.value(const [])
        : () async {
            try {
              return await loadHomeSections!();
            } catch (_) {
              return const <AndroidAutoHomeSection>[];
            }
          }();

    final results = await Future.wait<dynamic>([
      homeSectionsFuture,
      loadHistory(),
      _playlistGridCards(limit: 6, groupTitle: 'Tus playlists'),
    ]);

    final remoteSections = results[0] as List<AndroidAutoHomeSection>;
    final history = results[1] as List<LocalTrack>;
    final playlistCards = results[2] as List<DesktopMediaBrowseItem>;

    final output = <DesktopMediaBrowseItem>[];
    var insertedUserPlaylists = false;
    var includedSections = 0;

    for (var sIndex = 0; sIndex < remoteSections.length; sIndex++) {
      if (includedSections >= 6) break;
      final section = remoteSections[sIndex];
      final title = section.title.trim();
      if (title.isEmpty || section.items.isEmpty) continue;

      final sectionKey = 's$sIndex';
      final sectionTracks = section.items
          .whereType<AndroidAutoHomeTrack>()
          .map((item) => item.track)
          .toList(growable: false);
      if (sectionTracks.isNotEmpty) {
        _cachedRecSectionQueues[sectionKey] = sectionTracks;
      }

      final sectionBrowseItems = <DesktopMediaBrowseItem>[];
      for (final item in section.items.take(6)) {
        switch (item) {
          case AndroidAutoHomeTrack(:final track):
            sectionBrowseItems.add(
              DesktopMediaBrowseItem(
                id: '$_recTrackPrefix${Uri.encodeComponent(sectionKey)}|${Uri.encodeComponent(track.id)}',
                title: track.title,
                subtitle: track.artist.isEmpty ? 'Inútil Music' : track.artist,
                album: track.album,
                thumbnailUrl: _highResArtwork(track.thumbnailUrl),
                duration: track.duration,
                playable: true,
                extras: <String, dynamic>{contentStyleGroupTitleHintKey: title},
              ),
            );
          case AndroidAutoHomeCollection(
            :final title,
            :final browseId,
            :final subtitle,
            :final thumbnailUrl,
          ):
            if (browseId.trim().isEmpty) continue;
            sectionBrowseItems.add(
              DesktopMediaBrowseItem(
                id: '$_recCollectionPrefix${Uri.encodeComponent(browseId)}',
                title: title,
                subtitle: subtitle?.trim().isNotEmpty == true
                    ? subtitle!.trim()
                    : 'Mix recomendado',
                thumbnailUrl:
                    _highResArtwork(thumbnailUrl) ?? _tabIconPlaylists,
                playable: false,
                extras: <String, dynamic>{
                  contentStyleGroupTitleHintKey: section.title.trim(),
                  contentStylePlayableHintKey: contentStyleListValue,
                },
              ),
            );
          case AndroidAutoHomeArtist(:final name, :final thumbnailUrl):
            if (name.trim().isEmpty) continue;
            sectionBrowseItems.add(
              DesktopMediaBrowseItem(
                id: '$_recArtistPrefix${Uri.encodeComponent(name.trim())}',
                title: name.trim(),
                subtitle: 'Artista',
                thumbnailUrl: _highResArtwork(thumbnailUrl) ?? _tabIconExplore,
                playable: false,
                extras: <String, dynamic>{
                  contentStyleGroupTitleHintKey: section.title.trim(),
                  contentStylePlayableHintKey: contentStyleListValue,
                },
              ),
            );
        }
      }

      if (sectionBrowseItems.isEmpty) continue;
      output.addAll(sectionBrowseItems);
      includedSections++;

      // Place user playlists right after the first section (e.g. Seguir
      // escuchando) so both recommendations and personal playlists are right
      // at the top while driving.
      if (!insertedUserPlaylists && playlistCards.isNotEmpty) {
        output.addAll(playlistCards);
        insertedUserPlaylists = true;
      }
    }

    // Offline or empty remote feed fallback: always show local recent tracks +
    // playlists so Inicio is never blank in the car.
    if (output.isEmpty) {
      output.addAll(
        history
            .take(6)
            .map(
              (track) => _historyBrowseItem(
                track,
                groupTitle: 'Escuchado recientemente',
              ),
            ),
      );
      output.addAll(playlistCards);
    } else if (!insertedUserPlaylists && playlistCards.isNotEmpty) {
      output.addAll(playlistCards);
    }

    return output;
  }

  Future<List<DesktopMediaBrowseItem>> _exploreGridCards() async {
    if (loadExploreCategories == null) {
      return const <DesktopMediaBrowseItem>[];
    }
    List<AndroidAutoExploreCategory> categories;
    try {
      categories = await loadExploreCategories!();
    } catch (_) {
      return const <DesktopMediaBrowseItem>[];
    }

    _cachedExploreCategories.clear();
    return categories
        .take(18)
        .map((category) {
          _cachedExploreCategories[category.id] = category;
          return DesktopMediaBrowseItem(
            id: '$_exploreCategoryPrefix${Uri.encodeComponent(category.id)}',
            title: category.title,
            subtitle: 'Explorar',
            thumbnailUrl:
                _highResArtwork(category.artworkUrl) ?? _tabIconExplore,
            playable: false,
            extras: const <String, dynamic>{
              contentStyleBrowsableHintKey: contentStyleGridValue,
              contentStylePlayableHintKey: contentStyleListValue,
            },
          );
        })
        .toList(growable: false);
  }

  Future<List<DesktopMediaBrowseItem>> _exploreCategoryChildren(
    String categoryId,
  ) async {
    final category = _cachedExploreCategories[categoryId];
    if (category == null) {
      return const <DesktopMediaBrowseItem>[];
    }

    if (loadExploreCategoryPage != null) {
      try {
        final page = await loadExploreCategoryPage!(category);
        final items = <DesktopMediaBrowseItem>[];
        if (page.collections.isNotEmpty) {
          for (final collection in page.collections.take(12)) {
            if (collection.browseId.trim().isEmpty) continue;
            items.add(
              DesktopMediaBrowseItem(
                id: '$_recCollectionPrefix${Uri.encodeComponent(collection.browseId)}',
                title: collection.title,
                subtitle: collection.subtitle?.trim().isNotEmpty == true
                    ? collection.subtitle!.trim()
                    : category.title,
                thumbnailUrl:
                    _highResArtwork(collection.thumbnailUrl) ??
                    _tabIconPlaylists,
                playable: false,
                extras: const <String, dynamic>{
                  contentStyleGroupTitleHintKey: 'Playlists recomendadas',
                  contentStylePlayableHintKey: contentStyleListValue,
                },
              ),
            );
          }
        }
        if (page.tracks.isNotEmpty) {
          _cachedExploreTrackQueues[categoryId] = page.tracks;
          final encodedCat = Uri.encodeComponent(categoryId);
          for (final track in page.tracks.take(25)) {
            items.add(
              DesktopMediaBrowseItem(
                id: '$_exploreTrackPrefix$encodedCat|${Uri.encodeComponent(track.id)}',
                title: track.title,
                subtitle: track.artist.isEmpty ? category.title : track.artist,
                album: track.album,
                thumbnailUrl: _highResArtwork(track.thumbnailUrl),
                duration: track.duration,
                playable: true,
                extras: const <String, dynamic>{
                  contentStyleGroupTitleHintKey: 'Canciones',
                },
              ),
            );
          }
        }
        if (items.isNotEmpty) {
          return items;
        }
      } catch (_) {
        // Fall through to catalog search fallback.
      }
    }

    return search(category.searchQuery);
  }

  Future<List<DesktopMediaBrowseItem>> _collectionChildren(
    String browseId,
  ) async {
    if (loadCollectionTracks == null) {
      return const <DesktopMediaBrowseItem>[];
    }
    List<TrackInfo> tracks;
    try {
      tracks = await loadCollectionTracks!(browseId);
    } catch (_) {
      return const <DesktopMediaBrowseItem>[];
    }
    if (tracks.isEmpty) {
      return const <DesktopMediaBrowseItem>[];
    }
    _cachedCollectionQueues[browseId] = tracks;
    final encodedBrowseId = Uri.encodeComponent(browseId);
    return tracks
        .take(60)
        .map(
          (track) => DesktopMediaBrowseItem(
            id: '$_recCollectionTrackPrefix$encodedBrowseId|${Uri.encodeComponent(track.id)}',
            title: track.title,
            subtitle: track.artist.isEmpty ? 'Inútil Music' : track.artist,
            album: track.album,
            thumbnailUrl: _highResArtwork(track.thumbnailUrl),
            duration: track.duration,
            playable: true,
          ),
        )
        .toList(growable: false);
  }

  Future<List<DesktopMediaBrowseItem>> _librarySections() async {
    final results = await Future.wait<List<DesktopMediaBrowseItem>>([
      _playlistChildren(Playlist.favoritesId, groupTitle: 'Favoritos'),
      _downloadedLocalItems(groupTitle: 'Descargadas (sin conexión)'),
    ]);
    return <DesktopMediaBrowseItem>[...results[0], ...results[1]];
  }

  Future<List<LocalTrack>> _downloadedLocalTracks() async {
    final all = await loadLocalTracks();
    return all
        .where((track) => track.filePath.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<List<DesktopMediaBrowseItem>> _downloadedLocalItems({
    String? groupTitle,
  }) async {
    final localTracks = await _downloadedLocalTracks();
    return localTracks
        .take(100)
        .map((track) => _localBrowseItem(track, groupTitle: groupTitle))
        .toList(growable: false);
  }

  Future<List<DesktopMediaBrowseItem>> _playlistGridCards({
    int limit = 40,
    String? groupTitle,
  }) async {
    final playlists = await loadPlaylists();
    final visible = playlists
        .where(
          (playlist) => !playlist.isFavorites && playlist.deletedAt == null,
        )
        .take(limit)
        .toList(growable: false);
    if (visible.isEmpty) {
      return const <DesktopMediaBrowseItem>[];
    }

    final localTracks = await loadLocalTracks();
    final cards = await Future.wait(
      visible.map(
        (playlist) => _buildPlaylistCard(
          playlist,
          localTracks: localTracks,
          groupTitle: groupTitle,
        ),
      ),
    );
    return cards;
  }

  Future<DesktopMediaBrowseItem> _buildPlaylistCard(
    Playlist playlist, {
    required List<LocalTrack> localTracks,
    String? groupTitle,
  }) async {
    String? artwork;
    final customName = playlist.customArtworkFileName?.trim();
    if (customName != null &&
        customName.isNotEmpty &&
        resolveCustomPlaylistArtworkPath != null) {
      try {
        artwork = await resolveCustomPlaylistArtworkPath!(customName);
      } catch (_) {
        artwork = null;
      }
    }

    var trackCount = playlist.trackIds.length;
    final catalog = await loadCatalogPlaylist(playlist.id);
    if (catalog != null) {
      final items = catalogPlaylistPlaybackItems(catalog, localTracks);
      trackCount = items.length;
      if (artwork == null || artwork.isEmpty) {
        for (final item in items) {
          final candidate = _bestItemArtwork(item);
          if (candidate != null) {
            artwork = candidate;
            break;
          }
        }
      }
    }

    return DesktopMediaBrowseItem(
      id: '$_playlistPrefix${Uri.encodeComponent(playlist.id)}',
      title: playlist.name,
      subtitle: _trackCountLabel(trackCount),
      thumbnailUrl: artwork ?? _tabIconPlaylists,
      playable: false,
      extras: <String, dynamic>{
        contentStyleGroupTitleHintKey: ?groupTitle,
        contentStylePlayableHintKey: contentStyleListValue,
      },
    );
  }

  Future<List<DesktopMediaBrowseItem>> _playlistChildren(
    String playlistId, {
    int limit = 100,
    String? groupTitle,
  }) async {
    final catalog = await loadCatalogPlaylist(playlistId);
    if (catalog == null) {
      return const <DesktopMediaBrowseItem>[];
    }
    final localTracks = await loadLocalTracks();
    final items = catalogPlaylistPlaybackItems(catalog, localTracks);
    final encodedPlaylistId = Uri.encodeComponent(playlistId);
    return items
        .take(limit)
        .map((item) {
          final local = item.localTrack;
          final remote = item.remoteTrack;
          final title = local?.title ?? remote?.title ?? 'Inútil Music';
          final artist = local?.artist ?? remote?.artist ?? '';
          final album = local?.album ?? remote?.album;
          final duration = local?.duration ?? remote?.duration;
          return DesktopMediaBrowseItem(
            id: '$_playlistItemPrefix$encodedPlaylistId|${Uri.encodeComponent(item.entryId)}',
            title: title,
            subtitle: artist.isEmpty ? 'Inútil Music' : artist,
            album: album,
            thumbnailUrl: _bestItemArtwork(item),
            duration: duration,
            playable: true,
            extras: groupTitle == null
                ? null
                : <String, dynamic>{contentStyleGroupTitleHintKey: groupTitle},
          );
        })
        .toList(growable: false);
  }

  String? _bestItemArtwork(CatalogPlaybackItem item) {
    final candidate =
        item.remoteTrack?.thumbnailUrl ??
        item.localTrack?.thumbnailUrl ??
        item.localTrack?.catalogThumbnailUrl ??
        item.localTrack?.thumbnailPath;
    return _highResArtwork(candidate);
  }

  String? _highResArtwork(String? source) {
    final normalized = source?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return sizedGoogleArtworkSource(normalized, 640) ?? normalized;
  }

  DesktopMediaBrowseItem _historyBrowseItem(
    LocalTrack track, {
    String? groupTitle,
  }) => DesktopMediaBrowseItem(
    id: '$_historyPrefix${Uri.encodeComponent(track.id)}',
    title: track.title,
    subtitle: track.artist.isEmpty ? 'Inútil Music' : track.artist,
    album: track.album,
    thumbnailUrl: _highResArtwork(
      track.thumbnailUrl ?? track.catalogThumbnailUrl ?? track.thumbnailPath,
    ),
    duration: track.duration,
    playable: true,
    extras: groupTitle == null
        ? null
        : <String, dynamic>{contentStyleGroupTitleHintKey: groupTitle},
  );

  DesktopMediaBrowseItem _localBrowseItem(
    LocalTrack track, {
    String? groupTitle,
  }) => DesktopMediaBrowseItem(
    id: '$_localPrefix${Uri.encodeComponent(track.id)}',
    title: track.title,
    subtitle: track.artist.isEmpty ? 'Inútil Music' : track.artist,
    album: track.album,
    thumbnailUrl: _highResArtwork(
      track.thumbnailUrl ?? track.catalogThumbnailUrl ?? track.thumbnailPath,
    ),
    duration: track.duration,
    playable: true,
    extras: groupTitle == null
        ? null
        : <String, dynamic>{contentStyleGroupTitleHintKey: groupTitle},
  );

  LocalTrack? _findLocalById(List<LocalTrack> tracks, String id) {
    for (final track in tracks) {
      if (track.id == id) {
        return track;
      }
    }
    return null;
  }

  TrackInfo? _findRemoteById(List<TrackInfo>? tracks, String id) {
    if (tracks == null) return null;
    for (final track in tracks) {
      if (track.id == id) {
        return track;
      }
    }
    return null;
  }

  TrackInfo _fallbackRemoteTrack(String videoId) => TrackInfo(
    id: videoId,
    title: videoId,
    artist: '',
    url: 'https://www.youtube.com/watch?v=$videoId',
  );

  String _trackCountLabel(int count) =>
      count == 1 ? '1 canción' : '$count canciones';
}

import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/features/music/domain/entities/catalog_playlist.dart';
import 'package:inutil_music/features/music/domain/entities/catalog_track.dart';
import 'package:inutil_music/features/music/domain/entities/playlist.dart';
import 'package:inutil_music/features/music/domain/entities/playlist_entry.dart';
import 'package:inutil_music/features/music/presentation/providers/app_strings.dart';
import 'package:inutil_music/features/music/presentation/providers/music_providers.dart';
import 'package:inutil_music/features/music/presentation/widgets/track_library_quick_sheet.dart';
import 'package:inutil_music/services/player/player_service.dart';

void main() {
  group('SettingsState visualBackdropMode & save button config', () {
    test('derives unified PlayerVisualBackdropMode without conflicts', () {
      const base = SettingsState(
        downloadDirectory: '/tmp',
        language: AppLanguage.spanish,
        animatedArtworkEnabled: false,
        appleAnimatedArtworkEnabled: false,
        spotifyCanvasEnabled: false,
      );
      expect(base.visualBackdropMode, PlayerVisualBackdropMode.staticCover);

      expect(
        base.copyWith(animatedArtworkEnabled: true).visualBackdropMode,
        PlayerVisualBackdropMode.subtleMotion,
      );
      expect(
        base
            .copyWith(
              animatedArtworkEnabled: true,
              appleAnimatedArtworkEnabled: true,
            )
            .visualBackdropMode,
        PlayerVisualBackdropMode.appleAnimatedArtwork,
      );
      expect(
        base
            .copyWith(
              animatedArtworkEnabled: true,
              spotifyCanvasEnabled: true,
            )
            .visualBackdropMode,
        PlayerVisualBackdropMode.videoCanvas,
      );
    });

    test('PlayerSaveButtonAction parses codes and falls back to smart', () {
      expect(
        PlayerSaveButtonAction.fromCode('smart'),
        PlayerSaveButtonAction.smart,
      );
      expect(
        PlayerSaveButtonAction.fromCode('picker'),
        PlayerSaveButtonAction.picker,
      );
      expect(
        PlayerSaveButtonAction.fromCode('favorites_only'),
        PlayerSaveButtonAction.favoritesOnly,
      );
      expect(
        PlayerSaveButtonAction.fromCode('unknown'),
        PlayerSaveButtonAction.smart,
      );
      expect(
        PlayerSaveButtonAction.fromCode(null),
        PlayerSaveButtonAction.smart,
      );
    });
  });

  group('Track library membership detection', () {
    final now = DateTime(2026, 11, 24);

    test('detects remote YouTube track saved inside a user playlist', () {
      final playlist = Playlist(
        id: 'pl-roadtrip',
        name: 'Roadtrip',
        trackIds: const [],
        createdAt: now,
        updatedAt: now,
      );
      final catalog = CatalogPlaylist(
        playlist: playlist,
        entries: [
          PlaylistEntry(
            id: 'entry-1',
            playlistId: 'pl-roadtrip',
            position: 0,
            track: CatalogTrack.youtube(
              videoId: 'dQw4w9WgXcQ',
              title: 'Never Gonna Give You Up',
              artists: const ['Rick Astley'],
            ),
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );

      const snapshot = PlayerSnapshot(
        status: PlayerStatus.playing,
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        trackId: 'dQw4w9WgXcQ',
        sourceUrl: 'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
        isRemote: true,
      );

      expect(
        isSnapshotSavedInLibrary(
          catalogPlaylists: [catalog],
          snapshot: snapshot,
          isFavorite: false,
          savedTrackId: null,
        ),
        isTrue,
      );
    });

    test('ignores deleted (tombstoned) playlist entries', () {
      final playlist = Playlist(
        id: 'pl-roadtrip',
        name: 'Roadtrip',
        trackIds: const [],
        createdAt: now,
        updatedAt: now,
      );
      final catalog = CatalogPlaylist(
        playlist: playlist,
        entries: [
          PlaylistEntry(
            id: 'entry-1',
            playlistId: 'pl-roadtrip',
            position: 0,
            track: CatalogTrack.youtube(
              videoId: 'dQw4w9WgXcQ',
              title: 'Never Gonna Give You Up',
              artists: const ['Rick Astley'],
            ),
            createdAt: now,
            updatedAt: now,
            deletedAt: now,
          ),
        ],
      );

      const snapshot = PlayerSnapshot(
        status: PlayerStatus.playing,
        trackId: 'dQw4w9WgXcQ',
        sourceUrl: 'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
        isRemote: true,
      );

      expect(
        isSnapshotSavedInLibrary(
          catalogPlaylists: [catalog],
          snapshot: snapshot,
          isFavorite: false,
          savedTrackId: null,
        ),
        isFalse,
      );
    });
  });
}

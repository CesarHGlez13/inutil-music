import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/firebase/inutil_cloud_backup_service.dart';
import 'package:inutil_music/features/music/domain/entities/catalog_track.dart';
import 'package:inutil_music/features/music/domain/entities/playlist_entry.dart';
import 'package:inutil_music/services/storage/local_database_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TestDatabase extends LocalDatabaseService {
  _TestDatabase(this.path);

  final String path;

  @override
  Future<String> databasePath() async => path;
}

InutilCloudBackupService _buildService({
  required LocalDatabaseService db,
  required Map<String, Map<String, dynamic>> cloudDocs,
  required String Function() uidProvider,
}) {
  return InutilCloudBackupService(
    database: db,
    hooks: InutilCloudBackupHooks(
      currentUid: uidProvider,
      canSync: () => uidProvider().isNotEmpty,
      ensureFreshSession: () async => uidProvider().isNotEmpty,
      onPersistWrapped: () async {},
      onPullWrapped: () async {},
      getDocument: (path) async => cloudDocs[path],
      setDocument: (path, data) async {
        cloudDocs[path] = data;
        return true;
      },
      deleteDocument: (path) async {
        cloudDocs.remove(path);
        return true;
      },
    ),
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'restores catalog playlists (Spotify/CSV entries) after full reinstall',
    () async {
      final sandbox = await Directory.systemTemp.createTemp('inutil-cloud-1-');
      final dbA = _TestDatabase(p.join(sandbox.path, 'a.db'));
      final dbB = _TestDatabase(p.join(sandbox.path, 'b.db'));
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
        await sandbox.delete(recursive: true);
      });

      final cloud = <String, Map<String, dynamic>>{};
      var uid = 'user-1';
      final backupA = _buildService(
        db: dbA,
        cloudDocs: cloud,
        uidProvider: () => uid,
      );

      final now = DateTime.utc(2026, 11, 18, 8, 30);
      await dbA.createCatalogPlaylist(
        id: 'csv-111',
        name: 'Gym Favoritas',
        now: now,
      );
      await dbA.appendCatalogEntry(
        playlistId: 'csv-111',
        entryId: 'entry-1',
        track: CatalogTrack.youtube(
          videoId: 'dQw4w9WgXcQ',
          title: 'Track One',
          artists: const ['Artist A'],
          album: 'Album A',
          duration: const Duration(seconds: 210),
          thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
          sourceUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        ),
        now: now,
      );
      await dbA.appendCatalogEntry(
        playlistId: 'csv-111',
        entryId: 'entry-2',
        track: CatalogTrack.youtube(
          videoId: '9bZkp7q19f0',
          title: 'Track Two',
          artists: const ['Artist B'],
        ),
        now: now,
      );

      // Push inicial desde dispositivo A (pull inicial vacío marcado ok).
      await backupA.pushNow();
      expect(cloud.containsKey('users/user-1/data/backup_meta'), isTrue);
      expect(cloud.containsKey('users/user-1/data/backup_entries_0'), isTrue);

      // Simular dispositivo B recién reinstalado con entrada con localTrackId
      // huérfano para verificar que la clave foránea no bloquea el restore.
      final rawEntries =
          cloud['users/user-1/data/backup_entries_0']!['entries']
              as List<dynamic>;
      (rawEntries.first as Map<String, dynamic>)['localTrackId'] =
          'missing-local-id';

      final backupB = _buildService(
        db: dbB,
        cloudDocs: cloud,
        uidProvider: () => uid,
      );
      final summary = await backupB.pullAndRestoreIfEmpty();
      expect(backupB.lastRestoreHadChanges, isTrue);
      expect(summary, contains('1 playlists'));
      expect(summary, contains('2 canciones en listas'));

      final restoredPlaylists = await dbB.getCatalogPlaylists();
      expect(restoredPlaylists.map((p) => p.name), contains('Gym Favoritas'));

      final restoredCatalog = await dbB.getCatalogPlaylist('csv-111');
      expect(restoredCatalog, isNotNull);
      expect(restoredCatalog!.entries.length, 2);
      expect(restoredCatalog.entries[0].track.title, 'Track One');
      expect(restoredCatalog.entries[0].localTrackId, isNull);
      expect(restoredCatalog.entries[1].track.title, 'Track Two');
    },
  );

  test(
    'pushNow merges cloud playlists before uploading when reinstalling with new local list',
    () async {
      final sandbox = await Directory.systemTemp.createTemp('inutil-cloud-2-');
      final dbA = _TestDatabase(p.join(sandbox.path, 'a.db'));
      final dbB = _TestDatabase(p.join(sandbox.path, 'b.db'));
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
        await sandbox.delete(recursive: true);
      });

      final cloud = <String, Map<String, dynamic>>{};
      var uid = 'user-2';
      final now = DateTime.utc(2026, 11, 18, 8, 35);

      final backupA = _buildService(
        db: dbA,
        cloudDocs: cloud,
        uidProvider: () => uid,
      );
      await dbA.createCatalogPlaylist(id: 'csv-old', name: 'Mias', now: now);
      await dbA.appendCatalogEntry(
        playlistId: 'csv-old',
        entryId: 'entry-old',
        origin: PlaylistEntryOrigin.local,
        track: CatalogTrack.youtube(
          videoId: 'abc123def45',
          title: 'Saved Song',
          artists: const ['Saved Artist'],
        ),
        now: now,
      );
      await backupA.pushNow();

      // En B (reinstalado), el usuario crea una playlist nueva antes de que
      // corra el pull explícito. pushNow debe fusionar Mias en lugar de borrarla.
      final backupB = _buildService(
        db: dbB,
        cloudDocs: cloud,
        uidProvider: () => uid,
      );
      await dbB.createCatalogPlaylist(
        id: 'local-new',
        name: 'Nueva',
        now: now.add(const Duration(minutes: 1)),
      );
      await backupB.pushNow();

      final mergedLists = await dbB.getCatalogPlaylists();
      expect(mergedLists.map((p) => p.name).toSet(), {'Mias', 'Nueva'});

      final remoteMeta = cloud['users/user-2/data/backup_meta']!;
      final remoteNames = (remoteMeta['playlists'] as List<dynamic>)
          .map((e) => (e as Map)['name'])
          .toSet();
      expect(remoteNames, {'Mias', 'Nueva'});
    },
  );
}

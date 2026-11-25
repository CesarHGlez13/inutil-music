import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/features/music/data/datasources/playback_resume_store.dart';
import 'package:inutil_music/features/music/domain/entities/local_track.dart';
import 'package:inutil_music/features/music/domain/entities/track_info.dart';
import 'package:inutil_music/features/music/presentation/providers/music_providers.dart';
import 'package:inutil_music/features/music/presentation/widgets/mini_player.dart';
import 'package:inutil_music/services/player/player_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePlayerService implements PlayerService {
  PlayerSnapshot _snapshot = const PlayerSnapshot(status: PlayerStatus.idle);
  final List<Duration> seeks = <Duration>[];

  @override
  PlayerSnapshot get currentSnapshot => _snapshot;

  @override
  Stream<PlayerSnapshot> get snapshotStream => const Stream.empty();

  @override
  Future<void> playFile(
    String filePath, {
    required String trackId,
    required String title,
    required String artist,
    String? album,
    String? thumbnailUrl,
    String? sourceUrl,
    Duration? duration,
    String? queueEntryId,
  }) async {
    _snapshot = PlayerSnapshot(
      status: PlayerStatus.playing,
      playWhenReady: true,
      trackId: trackId,
      title: title,
      artist: artist,
      album: album,
      thumbnailUrl: thumbnailUrl,
      sourceUrl: sourceUrl ?? filePath,
      duration: duration,
      isRemote: false,
    );
  }

  @override
  Future<void> playUrl(
    String streamUrl, {
    required String trackId,
    required String title,
    required String artist,
    String? album,
    String? thumbnailUrl,
    String? sourceUrl,
    Duration? duration,
    Map<String, String>? httpHeaders,
    String? queueEntryId,
  }) async {
    _snapshot = PlayerSnapshot(
      status: PlayerStatus.playing,
      playWhenReady: true,
      trackId: trackId,
      title: title,
      artist: artist,
      album: album,
      thumbnailUrl: thumbnailUrl,
      sourceUrl: sourceUrl ?? streamUrl,
      duration: duration,
      isRemote: true,
    );
  }

  @override
  Future<void> pause() async {
    _snapshot = _snapshot.copyWith(
      status: PlayerStatus.paused,
      playWhenReady: false,
    );
  }

  @override
  Future<void> resume() async {
    _snapshot = _snapshot.copyWith(
      status: PlayerStatus.playing,
      playWhenReady: true,
    );
  }

  @override
  Future<void> stop() async {
    _snapshot = _snapshot.copyWith(
      status: PlayerStatus.stopped,
      playWhenReady: false,
    );
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    _snapshot = _snapshot.copyWith(position: position);
  }

  @override
  Future<void> setVolume(double volume) async {
    _snapshot = _snapshot.copyWith(volume: volume);
  }

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setCrossfade({
    required bool enabled,
    required Duration duration,
  }) async {}

  @override
  Future<void> setSkipSilence(bool enabled) async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('hasMiniPlayerPlayback', () {
    test('oculta el mini-reproductor en instalación nueva (idle) o detenido', () {
      expect(hasMiniPlayerPlayback(null), isFalse);
      expect(
        hasMiniPlayerPlayback(const PlayerSnapshot(status: PlayerStatus.idle)),
        isFalse,
      );
      expect(
        hasMiniPlayerPlayback(
          const PlayerSnapshot(
            status: PlayerStatus.stopped,
            trackId: 'abc',
            title: 'Canción',
          ),
        ),
        isFalse,
      );
    });

    test('muestra el mini-reproductor al restaurar en pausa o al reproducir', () {
      expect(
        hasMiniPlayerPlayback(
          const PlayerSnapshot(
            status: PlayerStatus.paused,
            trackId: 'dQw4w9WgXcQ',
            title: 'Mi canción',
            artist: 'Artista',
            position: Duration(minutes: 1, seconds: 42),
          ),
        ),
        isTrue,
      );
      expect(
        hasMiniPlayerPlayback(
          const PlayerSnapshot(
            status: PlayerStatus.playing,
            trackId: 'dQw4w9WgXcQ',
            title: 'Mi canción',
          ),
        ),
        isTrue,
      );
      expect(
        hasMiniPlayerPlayback(
          const PlayerSnapshot(
            status: PlayerStatus.failed,
            errorMessage: 'Sin conexión',
          ),
        ),
        isTrue,
      );
    });
  });

  group('PlaybackResumeStore', () {
    const store = PlaybackResumeStore();

    test('instalación limpia devuelve null', () async {
      expect(await store.load(), isNull);
    });

    test('guarda y restaura última canción + minuto y segundo exacto', () async {
      const track = TrackInfo(
        id: 'vid12345678',
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        album: 'A Night at the Opera',
        url: 'https://music.youtube.com/watch?v=vid12345678',
        thumbnailUrl: 'https://img.example/cover.jpg',
        duration: Duration(minutes: 5, seconds: 55),
        streamUrl: 'https://ephemeral-should-not-persist.example/audio.webm',
      );
      await store.save(
        SavedPlaybackSession(
          accountUid: 'uid_cesar',
          queue: const [SavedPlaybackQueueEntry(remote: track)],
          currentIndex: 0,
          positionMs: const Duration(minutes: 2, seconds: 14).inMilliseconds,
          durationMs: const Duration(minutes: 5, seconds: 55).inMilliseconds,
          repeatMode: PlaybackRepeatMode.all,
          shuffleEnabled: true,
          savedAtMs: 1700000000000,
        ),
      );

      final loaded = await store.load(expectedAccountUid: 'uid_cesar');
      expect(loaded, isNotNull);
      expect(loaded!.currentEntry?.remote?.id, 'vid12345678');
      expect(loaded.currentEntry?.remote?.title, 'Bohemian Rhapsody');
      // Ephemeral streamUrl must not be persisted.
      expect(loaded.currentEntry?.remote?.streamUrl, isNull);
      expect(loaded.clampedPosition, const Duration(minutes: 2, seconds: 14));
      expect(loaded.repeatMode, PlaybackRepeatMode.all);
      expect(loaded.shuffleEnabled, isTrue);

      // Account isolation: different user cannot see previous user's track.
      expect(await store.load(expectedAccountUid: 'uid_other'), isNull);
    });

    test('si se cerró justo al final de la pista, reinicia en 0:00', () {
      const track = TrackInfo(
        id: 'vid99999999',
        title: 'Final',
        artist: 'Artista',
        url: 'https://music.youtube.com/watch?v=vid99999999',
      );
      const session = SavedPlaybackSession(
        accountUid: null,
        queue: [SavedPlaybackQueueEntry(remote: track)],
        currentIndex: 0,
        positionMs: 199500,
        durationMs: 200000,
        repeatMode: PlaybackRepeatMode.off,
        shuffleEnabled: false,
        savedAtMs: 1700000000000,
      );
      expect(session.clampedPosition, Duration.zero);
    });

    test('descarta pista local si el archivo ya fue eliminado del disco', () async {
      final missingLocal = LocalTrack(
        id: 'loc-1',
        title: 'Archivo borrado',
        artist: 'Local',
        filePath: '/nonexistent/path/audio_deleted.mp3',
        addedAt: DateTime(2026),
      );
      await store.save(
        SavedPlaybackSession(
          accountUid: 'uid_cesar',
          queue: [SavedPlaybackQueueEntry(local: missingLocal)],
          currentIndex: 0,
          positionMs: 45000,
          durationMs: 180000,
          repeatMode: PlaybackRepeatMode.off,
          shuffleEnabled: false,
          savedAtMs: 1700000000000,
        ),
      );
      expect(await store.load(expectedAccountUid: 'uid_cesar'), isNull);
    });

    test('recorta colas largas manteniendo la canción actual centrada', () async {
      final entries = List<SavedPlaybackQueueEntry>.generate(
        60,
        (i) => SavedPlaybackQueueEntry(
          remote: TrackInfo(
            id: 'track_$i',
            title: 'Song $i',
            artist: 'Artist',
            url: 'https://music.youtube.com/watch?v=track_$i',
          ),
        ),
      );
      await store.save(
        SavedPlaybackSession(
          accountUid: 'uid_cesar',
          queue: entries,
          currentIndex: 42,
          positionMs: 65000,
          durationMs: 200000,
          repeatMode: PlaybackRepeatMode.off,
          shuffleEnabled: false,
          savedAtMs: 1700000000000,
        ),
      );
      final loaded = await store.load(expectedAccountUid: 'uid_cesar');
      expect(loaded, isNotNull);
      expect(loaded!.queue.length, 30);
      expect(loaded.currentEntry?.remote?.id, 'track_42');
    });
  });

  group('PlayerController cold-start restoration', () {
    test('sin sesión guardada inicia en idle y oculta el mini-reproductor', () async {
      final fakeService = _FakePlayerService();
      final container = ProviderContainer(
        overrides: [
          playerServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);

      final snap = await container.read(playerControllerProvider.future);
      expect(snap.status, PlayerStatus.idle);
      expect(hasMiniPlayerPlayback(snap), isFalse);
    });

    test('con sesión guardada restaura en pausa en el minuto y segundo exacto y persiste seek', () async {
      const store = PlaybackResumeStore();
      const savedTrack = TrackInfo(
        id: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        url: 'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
        duration: Duration(minutes: 3, seconds: 33),
      );
      await store.save(
        SavedPlaybackSession(
          accountUid: null,
          queue: const [SavedPlaybackQueueEntry(remote: savedTrack)],
          currentIndex: 0,
          positionMs: const Duration(minutes: 1, seconds: 42).inMilliseconds,
          durationMs: const Duration(minutes: 3, seconds: 33).inMilliseconds,
          repeatMode: PlaybackRepeatMode.one,
          shuffleEnabled: false,
          savedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      final fakeService = _FakePlayerService();
      final container = ProviderContainer(
        overrides: [
          playerServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);

      final snap = await container.read(playerControllerProvider.future);
      expect(snap.status, PlayerStatus.paused);
      expect(snap.playWhenReady, isFalse);
      expect(snap.trackId, 'dQw4w9WgXcQ');
      expect(snap.title, 'Never Gonna Give You Up');
      expect(snap.position, const Duration(minutes: 1, seconds: 42));
      expect(snap.repeatMode, PlaybackRepeatMode.one);
      expect(hasMiniPlayerPlayback(snap), isTrue);

      // Seeking while paused updates both snapshot and stored resume timestamp.
      await container
          .read(playerControllerProvider.notifier)
          .seek(const Duration(minutes: 2, seconds: 10));
      final updated = container.read(playerControllerProvider).value!;
      expect(updated.position, const Duration(minutes: 2, seconds: 10));

      final reloaded = await store.load();
      expect(reloaded, isNotNull);
      expect(
        reloaded!.clampedPosition,
        const Duration(minutes: 2, seconds: 10),
      );
    });
  });
}

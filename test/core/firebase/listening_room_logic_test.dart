import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/firebase/firebase_playback_sync_service.dart';
import 'package:inutil_music/core/firebase/listening_room_service.dart';
import 'package:inutil_music/features/music/presentation/providers/listening_room_providers.dart';
import 'package:inutil_music/features/music/presentation/providers/music_providers.dart';
import 'package:inutil_music/services/sharing/incoming_track_link_service.dart';

class _FakeIncomingLinkService implements IncomingTrackLinkService {
  final StreamController<Uri> controller = StreamController<Uri>.broadcast();

  @override
  Stream<Uri> get links => controller.stream;
}

void main() {
  group('Listening Rooms — deep links y normalización', () {
    test('incomingListeningRoomLinkProvider detecta links de sala e ignora tracks', () async {
      final fakeLinks = _FakeIncomingLinkService();
      final container = ProviderContainer(
        overrides: [
          incomingTrackLinkServiceProvider.overrideWithValue(fakeLinks),
        ],
      );
      addTearDown(() async {
        await fakeLinks.controller.close();
        container.dispose();
      });

      final received = <String>[];
      final sub = container.listen<AsyncValue<String>>(
        incomingListeningRoomLinkProvider,
        (_, next) => next.whenData(received.add),
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      fakeLinks.controller.add(Uri.parse('inutilmusic://track/dQw4w9WgXcQ'));
      fakeLinks.controller.add(Uri.parse('inutilmusic://room/k7m9p2'));
      fakeLinks.controller.add(Uri.parse('https://inutix.com/room/ab34cd'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(received, <String>['K7M9P2', 'AB34CD']);
    });

    test('canonicalListeningRoomTrackId normaliza URL, prefijos y videoId', () {
      expect(
        canonicalListeningRoomTrackId(
          sourceUrl: 'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
          rawTrackId: 'remote:dQw4w9WgXcQ',
        ),
        'dQw4w9WgXcQ',
      );
      expect(
        canonicalListeningRoomTrackId(
          sourceUrl: '',
          rawTrackId: 'dQw4w9WgXcQ',
        ),
        'dQw4w9WgXcQ',
      );
    });
  });

  group('Listening Rooms — resiliencia de red, salas huérfanas y cola votada', () {
    test('tolera hasta 2 microcortes consecutivos antes de cerrar la sala', () async {
      final store = <String, Map<String, dynamic>>{};
      var now = DateTime(2026, 11, 24, 21, 0, 0);
      var simulateDrop = false;

      Future<Map<String, dynamic>?> getter(String path) async {
        if (simulateDrop) return null;
        return store[path];
      }

      Future<bool> setter(String path, Map<String, dynamic> data) async {
        final existing = Map<String, dynamic>.from(store[path] ?? const {});
        existing.addAll(data);
        store[path] = existing;
        return true;
      }

      final host = ListeningRoomService(
        getDocument: getter,
        setDocument: setter,
        deleteDocument: (path) async => store.remove(path) != null,
        currentUid: () => 'uid_host',
        currentDisplayName: () => 'César',
        clock: () => now,
      );
      final guest = ListeningRoomService(
        getDocument: getter,
        setDocument: setter,
        deleteDocument: (path) async => store.remove(path) != null,
        currentUid: () => 'uid_guest',
        currentDisplayName: () => 'Sergio',
        clock: () => now,
      );
      addTearDown(() {
        host.dispose();
        guest.dispose();
      });

      expect(await host.createRoom(name: 'Sala Prueba'), isTrue);
      final code = host.room!.code;
      expect(await guest.joinRoom(code), isTrue);
      expect(guest.isGuest, isTrue);

      // 2 consecutive null polls (transient network drop) must NOT kick guest.
      simulateDrop = true;
      await guest.pollNow();
      expect(guest.isInRoom, isTrue);
      await guest.pollNow();
      expect(guest.isInRoom, isTrue);

      // Network recovers -> counter resets.
      simulateDrop = false;
      await guest.pollNow();
      expect(guest.isInRoom, isTrue);

      // Host actually closes room -> 3 consecutive missing polls closes cleanly.
      await host.leaveRoom();
      await guest.pollNow();
      await guest.pollNow();
      expect(guest.isInRoom, isTrue);
      await guest.pollNow();
      expect(guest.isInRoom, isFalse);
      expect(guest.lastError, contains('cerró la sala'));
    });

    test('rechaza unirse a una sala huérfana (>10 min sin latido del anfitrión)', () async {
      final createdAt = DateTime(2026, 11, 24, 20, 0, 0);
      var guestClock = DateTime(2026, 11, 24, 20, 15, 0);
      final store = <String, Map<String, dynamic>>{};

      Future<Map<String, dynamic>?> getter(String path) async => store[path];
      Future<bool> setter(String path, Map<String, dynamic> data) async {
        final existing = Map<String, dynamic>.from(store[path] ?? const {});
        existing.addAll(data);
        store[path] = existing;
        return true;
      }

      final host = ListeningRoomService(
        getDocument: getter,
        setDocument: setter,
        deleteDocument: (path) async => store.remove(path) != null,
        currentUid: () => 'uid_host',
        currentDisplayName: () => 'César',
        clock: () => createdAt,
      );
      final guest = ListeningRoomService(
        getDocument: getter,
        setDocument: setter,
        deleteDocument: (path) async => store.remove(path) != null,
        currentUid: () => 'uid_guest',
        currentDisplayName: () => 'Sergio',
        clock: () => guestClock,
      );
      addTearDown(() {
        host.dispose();
        guest.dispose();
      });

      expect(await host.createRoom(name: 'Sala Abandonada'), isTrue);
      final code = host.room!.code;

      expect(await guest.joinRoom(code), isFalse);
      expect(guest.lastError, contains('inactividad'));
    });

    test('ordena cola colaborativa por votos descendentes y popNextQueuedTrack solo funciona para el host', () async {
      final store = <String, Map<String, dynamic>>{};
      var now = DateTime(2026, 11, 24, 21, 0, 0);

      Future<Map<String, dynamic>?> getter(String path) async => store[path];
      Future<bool> setter(String path, Map<String, dynamic> data) async {
        final existing = Map<String, dynamic>.from(store[path] ?? const {});
        existing.addAll(data);
        store[path] = existing;
        return true;
      }

      final host = ListeningRoomService(
        getDocument: getter,
        setDocument: setter,
        deleteDocument: (path) async => store.remove(path) != null,
        currentUid: () => 'uid_host',
        currentDisplayName: () => 'César',
        clock: () => now,
      );
      final guest = ListeningRoomService(
        getDocument: getter,
        setDocument: setter,
        deleteDocument: (path) async => store.remove(path) != null,
        currentUid: () => 'uid_guest',
        currentDisplayName: () => 'Sergio',
        clock: () => now,
      );
      addTearDown(() {
        host.dispose();
        guest.dispose();
      });

      await host.createRoom(name: 'Fiesta');
      final code = host.room!.code;
      await guest.joinRoom(code);

      await guest.addToQueue(
        const ListeningRoomTrack(
          trackId: 'track_a',
          title: 'Canción A',
          artist: 'Artista A',
        ),
      );
      now = now.add(const Duration(seconds: 2));
      await guest.addToQueue(
        const ListeningRoomTrack(
          trackId: 'track_b',
          title: 'Canción B',
          artist: 'Artista B',
        ),
      );

      // Host upvotes track_b so it beats track_a (2 votes vs 1 vote).
      await host.pollNow();
      final itemB = host.room!.queue.firstWhere(
        (q) => q.track.trackId == 'track_b',
      );
      await host.toggleVote(itemB.id);

      // Guest cannot pop next track.
      expect(await guest.popNextQueuedTrack(), isNull);

      // Host pops highest-voted track first (track_b).
      final popped = await host.popNextQueuedTrack();
      expect(popped?.track.trackId, 'track_b');
    });

    test('modo invitado Listening Room suprime ruteo de Inutix Connect', () {
      final sync = InutilPlaybackSyncService.instance;
      expect(sync.isListeningRoomGuestMode, isFalse);
      sync.setListeningRoomGuestMode(true);
      expect(sync.isListeningRoomGuestMode, isTrue);
      expect(sync.isPlaybackRouteSuppressed, isTrue);
      sync.setListeningRoomGuestMode(false);
      expect(sync.isListeningRoomGuestMode, isFalse);
    });

    test('tolerancia a jitter de reloj: reloj invitado atrasado no declara host inactivo ni genera posición negativa', () {
      final hostNow = DateTime.utc(2026, 11, 26, 12, 0, 10);
      // Reloj del invitado está 5 segundos atrasado con respecto al host
      final guestBehindNow = DateTime.utc(2026, 11, 26, 12, 0, 5);

      final state = ListeningRoomState(
        code: 'JITTER',
        name: 'Sala Jitter',
        hostUid: 'host_uid',
        hostName: 'Cesar',
        currentTrack: const ListeningRoomTrack(
          trackId: 'track_1',
          title: 'Canción',
          artist: 'Artista',
          durationMs: 180000,
        ),
        positionMs: 15000,
        isPlaying: true,
        playbackUpdatedAtMs: hostNow.millisecondsSinceEpoch,
        createdAtMs: hostNow.millisecondsSinceEpoch,
        members: [
          ListeningRoomMember(
            uid: 'host_uid',
            displayName: 'Cesar',
            lastSeenMs: hostNow.millisecondsSinceEpoch,
            isHost: true,
          ),
        ],
      );

      // El host NO debe ser declarado inactivo aunque el reloj del invitado esté atrasado
      expect(state.isHostStaleAt(guestBehindNow), isFalse);

      // La posición estimada no debe decrecer por debajo de positionMs ni ser negativa
      expect(state.estimatedPositionMsAt(guestBehindNow), 15000);

      // Cuando avanza en el futuro del host, debe sumar el delta correctamente
      final futureGuest = hostNow.add(const Duration(seconds: 10));
      expect(state.estimatedPositionMsAt(futureGuest), 25000);
    });
  });
}

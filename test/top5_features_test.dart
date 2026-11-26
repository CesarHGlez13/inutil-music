import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/constants/app_constants.dart';
import 'package:inutil_music/core/firebase/firebase_firestore_service.dart';
import 'package:inutil_music/core/firebase/listening_room_service.dart';
import 'package:inutil_music/services/memories/echo_memory.dart';
import 'package:inutil_music/services/recommendations/algorithm_control_settings.dart';
import 'package:inutil_music/services/recommendations/personalized_recommendation_engine.dart';
import 'package:inutil_music/services/recommendations/recommendation_catalog.dart';
import 'package:inutil_music/services/recommendations/recommendation_feed_models.dart';
import 'package:inutil_music/services/recommendations/recommendation_repository.dart';
import 'package:inutil_music/services/recommendations/recommendation_storage_models.dart';
import 'package:inutil_music/services/recommendations/time_machine_service.dart';
import 'package:inutil_music/services/storage/local_database_service.dart';
import 'package:inutil_music/services/youtube_music/innertube_models.dart';
import 'package:inutil_music/services/youtube_music/track_versions_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // ---------------------------------------------------------------------------
  // 1. Centro de Control del Algoritmo
  // ---------------------------------------------------------------------------
  group('AlgorithmControlSettings & engine integration', () {
    test('rebalances weights to always total 100% and round-trips JSON', () {
      var settings = AlgorithmControlSettings.defaults;
      for (final slot in AlgorithmWeightSlot.values) {
        for (final target in const [0, 20, 50, 75, 100]) {
          settings = settings.withWeightAdjusted(slot, target);
          final sum =
              settings.knownPercent +
              settings.discoveryPercent +
              settings.forgottenPercent +
              settings.wildcardPercent;
          expect(sum, 100);
        }
      }

      final custom = AlgorithmControlSettings.forPreset(
        AlgorithmPreset.nostalgia,
      ).copyWith(antiRepetitionDays: 14);
      final restored = AlgorithmControlSettings.fromJsonString(
        custom.toJsonString(),
      );
      expect(restored, custom);
      expect(restored.antiRepetitionDays, 14);
      expect(
        AlgorithmControlSettings.forPreset(
          AlgorithmPreset.noAlgorithm,
        ).activePreset,
        AlgorithmPreset.noAlgorithm,
      );
    });

    test('algorithmDisabled returns only continueListening without network', () async {
      final now = DateTime.utc(2026, 11, 24, 12);
      final repo = _FakeRecommendationRepo(
        recentSeeds: [
          _seed('v1', 'Recent Hit', 'Artist A', playedAt: now.subtract(const Duration(hours: 2))),
        ],
        topSeeds: [
          _seed('v1', 'Recent Hit', 'Artist A', playedAt: now.subtract(const Duration(hours: 2))),
        ],
      );
      final catalog = _FakeRecommendationCatalog();
      final engine = PersonalizedRecommendationEngine(
        repository: repo,
        catalog: catalog,
        clock: () => now,
        config: PersonalizedRecommendationConfig(
          algorithmControl: AlgorithmControlSettings.forPreset(
            AlgorithmPreset.noAlgorithm,
          ),
        ),
      );

      final feed = await engine.refresh();
      expect(feed.sections.map((s) => s.kind), [
        PersonalizedSectionKind.continueListening,
      ]);
      expect(catalog.candidateRequests, 0);
    });

    test('nostalgia preset emits forgotten tracks and filters skipped seeds', () async {
      final now = DateTime.utc(2026, 11, 24, 12);
      final oldLove = _seed(
        'old_fav',
        'Old Classic',
        'Artist Gold',
        playedAt: now.subtract(const Duration(days: 60)),
        playCount: 9,
        completedCount: 8,
        totalListenedMs: 1800000,
        isFavorite: true,
      );
      final skippedOld = _seed(
        'old_skip',
        'Always Skipped',
        'Artist Skip',
        playedAt: now.subtract(const Duration(days: 45)),
        playCount: 4,
        completedCount: 0,
        totalListenedMs: 40000, // 10s avg -> skipped
      );
      final recent = _seed(
        'recent_1',
        'Today Song',
        'Artist Now',
        playedAt: now.subtract(const Duration(hours: 1)),
      );
      final repo = _FakeRecommendationRepo(
        recentSeeds: [recent],
        topSeeds: [oldLove, skippedOld, recent],
      );
      final catalog = _FakeRecommendationCatalog();
      final engine = PersonalizedRecommendationEngine(
        repository: repo,
        catalog: catalog,
        clock: () => now,
        config: PersonalizedRecommendationConfig(
          algorithmControl: AlgorithmControlSettings.forPreset(
            AlgorithmPreset.nostalgia,
          ),
        ),
      );

      final feed = await engine.refresh();
      final nostalgiaSection = feed.sections
          .where((s) => s.kind == PersonalizedSectionKind.nostalgia)
          .single;
      final trackIds = nostalgiaSection.items
          .whereType<PersonalizedTrackItem>()
          .map((t) => t.trackKey)
          .toList();
      expect(trackIds, contains('old_fav'));
      expect(trackIds, isNot(contains('old_skip')));
    });
  });

  // ---------------------------------------------------------------------------
  // 2. Echo Memory (SQLite v12 + Cross-source matching + Cloud JSON)
  // ---------------------------------------------------------------------------
  group('EchoMemory storage and matching', () {
    late Directory sandbox;
    late _TestLocalDb db;

    setUp(() async {
      sqfliteFfiInit();
      sandbox = await Directory.systemTemp.createTemp('inutil-echo-test-');
      db = _TestLocalDb(p.join(sandbox.path, AppConstants.databaseName));
    });

    tearDown(() async {
      await db.close();
      if (await sandbox.exists()) {
        await sandbox.delete(recursive: true);
      }
    });

    test('persists, queries, matches across local/stream, and validates DB v12', () async {
      final now = DateTime.utc(2026, 11, 24);
      final memory = EchoMemory(
        id: 'mem-1',
        trackKey: 'dQw4w9WgXcQ',
        titleArtistKey: normalizedEchoMemoryTitleArtistKey(
          'Nadie Sabe Lo Que Tiene (Official Video)',
          'Efecto Elegante',
        ),
        trackTitle: 'Nadie Sabe Lo Que Tiene',
        trackArtist: 'Efecto Elegante',
        note: 'Viaje a la playa con amigos',
        memoryDate: DateTime.utc(2024, 8, 15),
        showOnPlayback: true,
        createdAt: now,
        updatedAt: now,
      );

      await db.upsertEchoMemory(memory);
      final loaded = await db.getEchoMemories();
      expect(loaded, hasLength(1));
      expect(loaded.first.note, 'Viaje a la playa con amigos');

      // Matches both canonical videoId and a local copy with different ID
      expect(loaded.first.matchesTrack(trackKey: 'dQw4w9WgXcQ'), isTrue);
      expect(
        loaded.first.matchesTrack(
          trackKey: 'local-uuid-999',
          title: 'Nadie Sabe Lo Que Tiene [Remastered]',
          artist: 'Efecto Elegante',
        ),
        isTrue,
      );
      expect(
        loaded.first.matchesTrack(
          trackKey: 'other',
          title: 'Otra Canción',
          artist: 'Otro Artista',
        ),
        isFalse,
      );

      // Cloud JSON round-trip
      final fromCloud = EchoMemory.fromCloudJson(loaded.first.toCloudJson());
      expect(fromCloud, isNotNull);
      expect(fromCloud!.id, 'mem-1');
      expect(fromCloud.note, memory.note);

      // Backup validation accepts DB v12
      final path = await db.databasePath();
      await db.close();
      await expectLater(db.validateBackupDatabase(path), completes);

      await db.deleteEchoMemory('mem-1');
      expect(await db.getEchoMemories(), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Detector de Versiones
  // ---------------------------------------------------------------------------
  group('TrackVersionsService classification', () {
    test('classifies Original, Live, Acoustic, Remix, Cover, Remaster and filters noise', () {
      InnerTubeSong song(String id, String title, String artist) =>
          InnerTubeSong(
            videoId: id,
            title: title,
            artists: <String>[artist],
            duration: const Duration(minutes: 3, seconds: 30),
          );

      final candidates = <InnerTubeSong>[
        song('id_orig', 'Blinding Lights', 'The Weeknd'),
        song('id_live', 'Blinding Lights (Live at SoFi Stadium)', 'The Weeknd'),
        song('id_ac', 'Blinding Lights - Acoustic Version', 'The Weeknd'),
        song('id_rmx', 'Blinding Lights (Major Lazer Remix)', 'The Weeknd'),
        song('id_rem', 'Blinding Lights (Remastered 2024)', 'The Weeknd'),
        song('id_cov', 'Blinding Lights (Piano Cover)', 'Acoustic Covers'),
        song('id_noise', 'Completely Unrelated Hit', 'Random Artist'),
      ];

      final classified = TrackVersionsService.classifyCandidates(
        baseTitle: 'Blinding Lights (Official Audio)',
        primaryArtist: 'The Weeknd',
        candidates: candidates,
        currentVideoId: 'id_orig',
      );

      final byId = {for (final c in classified) c.song.videoId: c};
      expect(byId.containsKey('id_noise'), isFalse);
      expect(byId['id_orig']?.kind, TrackVersionKind.original);
      expect(byId['id_orig']?.isCurrentTrack, isTrue);
      expect(byId['id_live']?.kind, TrackVersionKind.live);
      expect(byId['id_ac']?.kind, TrackVersionKind.acoustic);
      expect(byId['id_rmx']?.kind, TrackVersionKind.remix);
      expect(byId['id_rem']?.kind, TrackVersionKind.remaster);
      expect(byId['id_cov']?.kind, TrackVersionKind.cover);
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Máquina del Tiempo Musical
  // ---------------------------------------------------------------------------
  group('TimeMachineAnalyzer', () {
    test('builds onThisDate, forgottenFavorites, and monthly capsules accurately', () {
      final now = DateTime.utc(2026, 11, 24, 12);
      PlaybackEvent ev(
        String sid,
        String id,
        String title,
        String artist,
        DateTime when, {
        int listenedMs = 180000,
      }) => PlaybackEvent(
        sessionId: sid,
        trackId: id,
        videoId: id,
        title: title,
        artists: <String>[artist],
        source: PlaybackEventSource.streaming,
        startedAt: when,
        playedAt: when,
        listenedMs: listenedMs,
        completed: true,
      );

      final events = <PlaybackEvent>[
        // A year ago (Nov 2025) - loved & forgotten!
        ev('s1', 't_old', 'Memorias 2025', 'Artista Retro', DateTime.utc(2025, 11, 10)),
        ev('s2', 't_old', 'Memorias 2025', 'Artista Retro', DateTime.utc(2025, 11, 12)),
        ev('s3', 't_old', 'Memorias 2025', 'Artista Retro', DateTime.utc(2025, 11, 15)),
        // 40 days ago (Oct 2026) - forgotten!
        ev('s4', 't_oct', 'Octubre Vibe', 'Banda Otoño', DateTime.utc(2026, 10, 10)),
        ev('s5', 't_oct', 'Octubre Vibe', 'Banda Otoño', DateTime.utc(2026, 10, 12)),
        // Yesterday (Nov 2026) - NOT forgotten
        ev('s6', 't_now', 'Canción Hoy', 'Artista Actual', now.subtract(const Duration(days: 1))),
        ev('s7', 't_now', 'Canción Hoy', 'Artista Actual', now.subtract(const Duration(hours: 2))),
      ];

      final snapshot = TimeMachineAnalyzer.analyze(events, now: now);
      expect(snapshot.totalTrackedPlays, 7);
      expect(snapshot.onThisDateTracks.map((t) => t.trackKey), contains('t_old'));
      expect(
        snapshot.forgottenFavorites.map((t) => t.trackKey),
        containsAll(<String>['t_old', 't_oct']),
      );
      expect(
        snapshot.forgottenFavorites.map((t) => t.trackKey),
        isNot(contains('t_now')),
      );
      expect(snapshot.monthlyCapsules.map((m) => m.monthKey), [
        '2026-11',
        '2026-10',
        '2025-11',
      ]);
      expect(snapshot.monthlyCapsules.last.topArtist, 'Artista Retro');
    });
  });

  // ---------------------------------------------------------------------------
  // 5. Listening Rooms
  // ---------------------------------------------------------------------------
  group('ListeningRoomService', () {
    test('parses room codes & links, bypasses relay, and compensates drift', () {
      expect(ListeningRoomService.parseRoomCode('k7m9p2'), 'K7M9P2');
      expect(
        ListeningRoomService.parseRoomCode('inutilmusic://room/k7m9p2'),
        'K7M9P2',
      );
      expect(
        ListeningRoomService.parseRoomCode('https://inutilmusic.com/room/ab12cd'),
        'AB12CD',
      );
      expect(
        InutilFirestoreService.shouldBypassRelay('listening_rooms/K7M9P2'),
        isTrue,
      );

      final t0 = DateTime.utc(2026, 11, 24, 12, 0, 0);
      final room = ListeningRoomState(
        code: 'K7M9P2',
        name: 'Sala Test',
        hostUid: 'host1',
        hostName: 'Cesar',
        currentTrack: const ListeningRoomTrack(
          trackId: 'vid1',
          title: 'Song 1',
          artist: 'Artist 1',
          durationMs: 200000,
        ),
        positionMs: 10000,
        isPlaying: true,
        playbackUpdatedAtMs: t0.millisecondsSinceEpoch,
        createdAtMs: t0.millisecondsSinceEpoch,
      );
      expect(
        room.estimatedPositionMsAt(t0.add(const Duration(seconds: 5))),
        15000,
      );
      expect(
        ListeningRoomState.shouldResyncPosition(localMs: 14500, targetMs: 15000),
        isFalse,
      );
      expect(
        ListeningRoomState.shouldResyncPosition(localMs: 12000, targetMs: 15000),
        isTrue,
      );
    });

    test('host create -> guest join -> collaborative upvoted queue -> reaction -> chat -> leave', () async {
      final store = <String, Map<String, dynamic>>{};
      var clockNow = DateTime.utc(2026, 11, 24, 12, 0, 0);

      Future<Map<String, dynamic>?> getDoc(String path) async =>
          store[path] == null ? null : Map<String, dynamic>.from(store[path]!);
      Future<bool> setDoc(String path, Map<String, dynamic> data) async {
        final existing = store[path] ?? <String, dynamic>{};
        store[path] = <String, dynamic>{...existing, ...data};
        return true;
      }
      Future<bool> delDoc(String path) async {
        store.remove(path);
        return true;
      }

      final host = ListeningRoomService(
        getDocument: getDoc,
        setDocument: setDoc,
        deleteDocument: delDoc,
        currentUid: () => 'uid_host',
        currentDisplayName: () => 'Cesar',
        clock: () => clockNow,
      );
      final guest = ListeningRoomService(
        getDocument: getDoc,
        setDocument: setDoc,
        deleteDocument: delDoc,
        currentUid: () => 'uid_guest',
        currentDisplayName: () => 'Amigo',
        clock: () => clockNow,
      );
      addTearDown(() {
        host.dispose();
        guest.dispose();
      });

      expect(await host.createRoom(name: 'Noche Chill'), isTrue);
      final code = host.room!.code;
      expect(host.isHost, isTrue);

      expect(await guest.joinRoom('inutilmusic://room/$code'), isTrue);
      expect(guest.isGuest, isTrue);
      expect(guest.room!.members.length, 2);

      // Add 2 songs and upvote the 2nd one so it jumps to #1 in sortedQueue
      await guest.addToQueue(
        const ListeningRoomTrack(trackId: 't1', title: 'First', artist: 'A'),
      );
      clockNow = clockNow.add(const Duration(seconds: 1));
      await guest.addToQueue(
        const ListeningRoomTrack(trackId: 't2', title: 'Second', artist: 'B'),
      );
      await host.pollNow();
      final secondId = host.room!.queue.last.id;
      await host.toggleVote(secondId);

      expect(host.room!.sortedQueue.first.track.trackId, 't2');
      expect(host.room!.sortedQueue.first.votes, 2);

      // Reactions & Chat
      await guest.sendReaction('🔥');
      await guest.sendMessage('Temazo!');
      await host.pollNow();
      expect(host.room!.messages.last.text, 'Temazo!');
      expect(host.recentBurstReactions.last.emoji, '🔥');

      // Host pops top-voted track
      final popped = await host.popNextQueuedTrack();
      expect(popped?.track.trackId, 't2');

      // Host closes room -> guest sees room closed after consecutive missing polls
      await host.leaveRoom();
      await guest.pollNow();
      await guest.pollNow();
      await guest.pollNow();
      expect(guest.isInRoom, isFalse);
    });
  });
}

RecommendationSeed _seed(
  String id,
  String title,
  String artist, {
  required DateTime playedAt,
  int playCount = 3,
  int completedCount = 3,
  int totalListenedMs = 540000,
  bool? isFavorite,
}) {
  return RecommendationSeed(
    trackKey: id,
    trackId: id,
    videoId: id,
    title: title,
    artists: <String>[artist],
    source: PlaybackEventSource.streaming,
    playCount: playCount,
    totalListenedMs: totalListenedMs,
    completedCount: completedCount,
    lastPlayedAt: playedAt,
    isFavorite: isFavorite,
  );
}

class _FakeRecommendationRepo implements RecommendationRepository {
  _FakeRecommendationRepo({
    required this.recentSeeds,
    required this.topSeeds,
  });

  final List<RecommendationSeed> recentSeeds;
  final List<RecommendationSeed> topSeeds;
  RecommendationFeedCache? _savedFeed;

  @override
  int get generation => 1;

  @override
  Future<List<RecommendationSeed>> getTopSeeds({
    required int limit,
    DateTime? since,
    int minListenedMs = 30000,
  }) async => topSeeds;

  @override
  Future<List<RecommendationSeed>> getRecentSeeds({
    required int limit,
    DateTime? since,
    int minListenedMs = 30000,
  }) async => recentSeeds;

  @override
  Future<Set<String>> getLibraryTrackKeys() async => const <String>{};

  @override
  Future<List<RelatedTrackCandidate>> getRelatedCandidates(
    String seedKey, {
    required Duration ttl,
    required DateTime now,
  }) async => const <RelatedTrackCandidate>[];

  @override
  Future<bool> replaceRelatedCandidates({
    required String seedKey,
    required List<RelatedTrackCandidate> candidates,
    required DateTime fetchedAt,
    required int expectedGeneration,
  }) async => true;

  @override
  Future<RecommendationFeedCache?> loadFeed(String feedKey) async => _savedFeed;

  @override
  Future<bool> deleteFeed(
    String feedKey, {
    required int expectedGeneration,
  }) async {
    _savedFeed = null;
    return true;
  }

  @override
  Future<bool> saveFeed(
    RecommendationFeedCache feed, {
    required int expectedGeneration,
  }) async {
    _savedFeed = feed;
    return true;
  }
}

class _FakeRecommendationCatalog implements RecommendationCatalog {
  int candidateRequests = 0;

  @override
  Future<SeedRecommendationCandidates> getCandidates(
    RecommendationSeed seed, {
    required int limit,
  }) async {
    candidateRequests += 1;
    return SeedRecommendationCandidates(
      tracks: const <RelatedTrackCandidate>[],
    );
  }

  @override
  Future<List<RecommendationRelease>> getArtistReleases(
    String artistBrowseId, {
    required int limit,
  }) async => const <RecommendationRelease>[];
}

class _TestLocalDb extends LocalDatabaseService {
  _TestLocalDb(this.path);

  final String path;

  @override
  Future<String> databasePath() async => path;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/firebase/firebase_playback_sync_service.dart';

/// Sesión que el **mando** guarda del altavoz remoto. [stamp] es el instante en
/// que ese dato se escribió: todo el bug del "reproductor colgado" gira
/// alrededor de él (medido 2026-11-20: `playback_session/current` congelado en
/// 11:49:52Z mientras la PC seguía avanzando hasta 186091/186161).
PlaybackSyncSession speaker({
  required DateTime stamp,
  int positionMs = 5611,
  int durationMs = 186161,
  bool isPlaying = true,
  String activeDeviceId = 'pc-de-cesar',
  String trackId = 'ScgXrU_LHXg',
}) {
  return PlaybackSyncSession(
    activeDeviceId: activeDeviceId,
    activeDeviceName: 'PC de César (Ubuntu)',
    activeDevicePlatform: 'linux',
    trackId: trackId,
    title: 'POR SUS BESOS',
    artist: 'Tito Double P',
    positionMs: positionMs,
    durationMs: durationMs,
    isPlaying: isPlaying,
    updatedAt: stamp,
  );
}

void main() {
  final now = DateTime.utc(2026, 11, 20, 12, 0, 0);

  group('estimatedPositionMs: la barra debe avanzar entre escrituras', () {
    test('contabiliza el tiempo transcurrido desde updatedAt', () {
      final s = speaker(stamp: now.subtract(const Duration(seconds: 6)));
      expect(s.estimatedPositionMsAt(now), greaterThan(s.positionMs));
      expect(s.estimatedPositionMsAt(now), closeTo(s.positionMs + 6000, 1500));
    });

    test('se topa en el final de la canción, nunca pasa de la duración', () {
      final s = speaker(stamp: now.subtract(const Duration(minutes: 30)));
      expect(s.estimatedPositionMsAt(now), equals(s.durationMs));
    });

    test('en pausa la posición estimada es la reportada, sin inventar', () {
      final s = speaker(
        stamp: now.subtract(const Duration(minutes: 30)),
        isPlaying: false,
      );
      expect(s.estimatedPositionMsAt(now), equals(s.positionMs));
    });
  });

  group('sessionIsGhost: un "reproduciendo" que ya no se refresca es falso', () {
    test('playing + snapshot viejo (el altavoz dejó de escribir) → fantasma', () {
      final s = speaker(stamp: now.subtract(const Duration(minutes: 28)));
      expect(InutilPlaybackSyncService.sessionIsGhost(s, now: now), isTrue);
    });

    test('playing + snapshot fresco (el altavoz escribe cada ~8 s) → válido', () {
      final s = speaker(stamp: now.subtract(const Duration(seconds: 6)));
      expect(InutilPlaybackSyncService.sessionIsGhost(s, now: now), isFalse);
    });

    test('justo por debajo del umbral sigue siendo válido', () {
      final s = speaker(stamp: now.subtract(const Duration(seconds: 19)));
      expect(InutilPlaybackSyncService.sessionIsGhost(s, now: now), isFalse);
    });

    test('pausa, aunque sea vieja, es información real: no es fantasma', () {
      final s = speaker(
        stamp: now.subtract(const Duration(minutes: 28)),
        isPlaying: false,
      );
      expect(InutilPlaybackSyncService.sessionIsGhost(s, now: now), isFalse);
    });
  });

  group('visibleSession: lo que el mando debe mostrar', () {
    test('snapshot local "reproduciendo" congelado → NO sale como playing', () {
      final ghost = speaker(
        stamp: now.subtract(const Duration(minutes: 28)),
        activeDeviceId: 'telefono',
      );
      final shown = InutilPlaybackSyncService.visibleSession(
        remote: null,
        local: ghost,
        now: now,
      );
      expect(shown, isNotNull);
      expect(shown!.isPlaying, isFalse);
      expect(shown.positionMs, equals(shown.durationMs));
    });

    test('sin sesión remota y snapshot local fresco → sí es la sesión', () {
      final local = speaker(stamp: now.subtract(const Duration(seconds: 3)));
      expect(
        InutilPlaybackSyncService.visibleSession(
          remote: null,
          local: local,
          now: now,
        )
            ?.trackId,
        equals(local.trackId),
      );
    });

    test('la sesión remota manda aunque el local esté congelado', () {
      final remote = speaker(stamp: now.subtract(const Duration(seconds: 6)));
      final ghost = speaker(
        stamp: now.subtract(const Duration(minutes: 28)),
        activeDeviceId: 'telefono',
        trackId: 'BOHEMIAN_RHAPSODY',
      );
      expect(
        InutilPlaybackSyncService.visibleSession(
          remote: remote,
          local: ghost,
          now: now,
        )
            ?.trackId,
        equals(remote.trackId),
      );
    });

    test('altavoz muerto: se marca terminada, no "reproduciendo" eterno', () {
      // Reporta "reproduciendo" desde hace 28 min sin un solo refresco: el
      // altavoz dejó de escribir. El mando debe mostrarla TERMINADA (y poder
      // avanzar la cola), no colgada fingiendo reproducción.
      final stuck = speaker(stamp: now.subtract(const Duration(minutes: 28)));
      final shown = InutilPlaybackSyncService.visibleSession(
        remote: stuck,
        local: null,
        now: now,
      );
      expect(shown!.isPlaying, isFalse);
      expect(shown.positionMs, equals(stuck.durationMs));
    });

    test('documento vacío (sin canción) → nada que mostrar', () {
      final empty = PlaybackSyncSession(
        activeDeviceId: 'pc-de-cesar',
        activeDeviceName: 'PC de César (Ubuntu)',
        activeDevicePlatform: 'linux',
        trackId: '',
        updatedAt: now,
      );
      expect(
        InutilPlaybackSyncService.visibleSession(
          remote: empty,
          local: null,
          now: now,
        ),
        isNull,
      );
    });
  });

  group('deviceIsCurrentSpeaker: quién manda el audio', () {
    test('mando que acaba de ceder la reproducción NO es el altavoz', () {
      expect(
        InutilPlaybackSyncService.deviceIsCurrentSpeaker(
          remote: null,
          deviceId: 'telefono',
          awaitingRemoteSpeaker: true,
        ),
        isFalse,
      );
    });

    test('sin cesión pendiente y sin sesión remota → sí es el altavoz', () {
      expect(
        InutilPlaybackSyncService.deviceIsCurrentSpeaker(
          remote: null,
          deviceId: 'telefono',
          awaitingRemoteSpeaker: false,
        ),
        isTrue,
      );
    });

    test('sesión remota que nombra a otro equipo → el altavoz es el otro', () {
      final remote = speaker(stamp: now);
      expect(
        InutilPlaybackSyncService.deviceIsCurrentSpeaker(
          remote: remote,
          deviceId: 'telefono',
          awaitingRemoteSpeaker: false,
        ),
        isFalse,
      );
      expect(
        InutilPlaybackSyncService.deviceIsCurrentSpeaker(
          remote: remote,
          deviceId: 'pc-de-cesar',
          awaitingRemoteSpeaker: true,
        ),
        isTrue,
      );
    });
  });

  group('shouldAdoptDocument: el mando debe re-adoptar el estado del altavoz', () {
    test('documento con updatedAt IGUAL al guardado se vuelve a adoptar', () {
      // Bug medido: con `isAfter` estricto, un documento que vuelve a igualar
      // el stamp ya guardado nunca se re-adopta y el mando se queda colgado.
      final stored = speaker(stamp: now);
      final doc = speaker(stamp: now);
      expect(
        InutilPlaybackSyncService.shouldAdoptDocument(stored: stored, doc: doc),
        isTrue,
      );
    });

    test('documento más viejo que lo guardado NO se adopta (no pisar)', () {
      final stored = speaker(stamp: now);
      final old = speaker(stamp: now.subtract(const Duration(minutes: 28)));
      expect(
        InutilPlaybackSyncService.shouldAdoptDocument(stored: stored, doc: old),
        isFalse,
      );
    });

    test('documento más nuevo siempre se adopta', () {
      final stored = speaker(stamp: now.subtract(const Duration(seconds: 9)));
      final fresh = speaker(stamp: now);
      expect(
        InutilPlaybackSyncService.shouldAdoptDocument(stored: stored, doc: fresh),
        isTrue,
      );
    });
  });

  group('declaredSpeakerIsLive: el altavoz nombrado tiene que existir', () {
    test('sesión nula → manda lo local', () {
      expect(
        InutilPlaybackSyncService.declaredSpeakerIsLive(
          session: null,
          myDeviceId: 'telefono',
          liveDeviceIds: {},
        ),
        isTrue,
      );
    });

    test('el altavoz nombrado somos nosotros → válido', () {
      final own = speaker(stamp: now, activeDeviceId: 'telefono');
      expect(
        InutilPlaybackSyncService.declaredSpeakerIsLive(
          session: own,
          myDeviceId: 'telefono',
          liveDeviceIds: {},
        ),
        isTrue,
      );
    });

    test('altavoz nombrado con presencia viva → válido', () {
      final remote = speaker(stamp: now);
      expect(
        InutilPlaybackSyncService.declaredSpeakerIsLive(
          session: remote,
          myDeviceId: 'telefono',
          liveDeviceIds: {'pc-de-cesar'},
        ),
        isTrue,
      );
    });

    test('altavoz vacío (sesión heredada) no secuestra el audio', () {
      final blank = speaker(stamp: now, activeDeviceId: '');
      expect(
        InutilPlaybackSyncService.declaredSpeakerIsLive(
          session: blank,
          myDeviceId: 'telefono',
          liveDeviceIds: {},
        ),
        isTrue,
      );
    });

    test('id fantasma → no es altavoz, aunque la nube lo nombre', () {
      // Medido 2026-11-20 16:18 CST: `playback_session/current` nombraba
      // `activeDeviceId = c90ec6c7-…`, que no estaba en `users/{uid}/devices`
      // (los 7 documentos eran otros ids) ni respondía a `/api/ping`. El
      // Xiaomi se quedó de mando y su reproducción local se congeló en
      // 0:08 / 3:51, porque solo el altavoz escribe la sesión en la nube.
      final ghost = speaker(
        stamp: now,
        activeDeviceId: 'c90ec6c7-7d12-4a12-879b-e236156b1f04',
      );
      expect(
        InutilPlaybackSyncService.declaredSpeakerIsLive(
          session: ghost,
          myDeviceId: '20ebcfb7-b580-4b1b-8ea2-28a3b694c0aa',
          liveDeviceIds: {'20ebcfb7-b580-4b1b-8ea2-28a3b694c0aa'},
        ),
        isFalse,
      );
    });
  });

  group('altavoz fantasma: el mando recupera su propio audio', () {
    final ghost = speaker(stamp: now, activeDeviceId: 'c90ec6c7');

    test('altavoz nombrado muerto y sin cesión pendiente → manda el local', () {
      expect(
        InutilPlaybackSyncService.deviceIsCurrentSpeaker(
          remote: ghost,
          deviceId: 'telefono',
          awaitingRemoteSpeaker: false,
          speakerIsLive: false,
        ),
        isTrue,
      );
    });

    test('mando dentro de la gracia de cesión NO se declara altavoz', () {
      expect(
        InutilPlaybackSyncService.deviceIsCurrentSpeaker(
          remote: ghost,
          deviceId: 'telefono',
          awaitingRemoteSpeaker: true,
          speakerIsLive: false,
        ),
        isFalse,
      );
    });

    test('altavoz vivo nombrado → el altavoz sigue siendo el otro', () {
      final remote = speaker(stamp: now);
      expect(
        InutilPlaybackSyncService.deviceIsCurrentSpeaker(
          remote: remote,
          deviceId: 'telefono',
          awaitingRemoteSpeaker: false,
          speakerIsLive: true,
        ),
        isFalse,
      );
    });

    test('sin pasar speakerIsLive el comportamiento queda intacto', () {
      final remote = speaker(stamp: now);
      expect(
        InutilPlaybackSyncService.deviceIsCurrentSpeaker(
          remote: remote,
          deviceId: 'telefono',
          awaitingRemoteSpeaker: false,
        ),
        isFalse,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/firebase/firebase_playback_sync_service.dart';

/// Pruebas del relay de Inútil Connect por Firestore.
///
/// Son todas funciones puras (`@visibleForTesting`): no tocan la red, así que
/// documentan el contrato exacto que hace falta para que el mando a distancia
/// liste y controle un PC que no está en el mismo Wi-Fi.
void main() {
  // `isOnlineNow` y el TTL comparan contra el reloj real, así que las marcas
  // de tiempo del fixture se derivan de `DateTime.now()`.
  final now = DateTime.now();

  LanDevicePeer lanPeer({
    required String deviceId,
    String name = 'PC de César (Ubuntu)',
    String ip = '192.168.100.24',
    bool isHost = true,
    String appVersion = '2.5.8+258',
    DateTime? lastSeen,
  }) =>
      LanDevicePeer(
        ip: ip,
        port: 52445,
        deviceId: deviceId,
        deviceName: name,
        platform: 'linux',
        isHost: isHost,
        appVersion: appVersion,
        lastSeen: lastSeen ?? now,
      );

  LanDevicePeer cloudPeer({
    required String deviceId,
    String name = 'PC de César (Ubuntu)',
    bool isHost = true,
    String appVersion = '',
    DateTime? lastSeen,
  }) =>
      LanDevicePeer(
        ip: '',
        port: 52445,
        deviceId: deviceId,
        deviceName: name,
        platform: 'linux',
        isHost: isHost,
        fromCloud: true,
        appVersion: appVersion,
        lastSeen: lastSeen ?? now,
      );

  group('peerFromCloudDoc', () {
    test('acepta un PC en línea y lo marca como destino alcanzable sólo por la nube', () {
      final peer = InutilPlaybackSyncService.peerFromCloudDoc(
        {
          'deviceId': 'pc_linux_1',
          'name': 'Torre de César',
          'platform': 'linux',
          'isHost': true,
          'isOnline': true,
          'lanPort': 52445,
          'appVersion': '2.5.8+258',
          'lastSeenMs': now.millisecondsSinceEpoch,
        },
        myDeviceId: 'phone_honor_1',
        now: now,
      );

      expect(peer, isNotNull);
      expect(peer!.deviceId, 'pc_linux_1');
      expect(peer.deviceName, 'Torre de César');
      expect(peer.isHost, isTrue);
      expect(peer.fromCloud, isTrue);
      // La IP local nunca se fía: sin anuncio UDP no hay forma de alcanzarla.
      expect(peer.isCloudOnly, isTrue);
      expect(peer.isOnlineNow, isTrue);
    });

    test('ignora este mismo equipo, los apagados y los heartbeat caducados', () {
      LanDevicePeer? parse(Map<String, dynamic> doc) =>
          InutilPlaybackSyncService.peerFromCloudDoc(
            doc,
            myDeviceId: 'phone_honor_1',
            now: now,
          );

      expect(
        parse({
          'deviceId': 'phone_honor_1',
          'isOnline': true,
          'lastSeenMs': now.millisecondsSinceEpoch,
        }),
        isNull,
      );
      expect(
        parse({
          'deviceId': 'pc_linux_1',
          'isOnline': false,
          'lastSeenMs': now.millisecondsSinceEpoch,
        }),
        isNull,
      );
      expect(
        parse({
          'deviceId': 'pc_linux_1',
          'isOnline': true,
          'lastSeenMs': now
              .subtract(InutilPlaybackSyncService.cloudPeerTtl +
                  const Duration(seconds: 1))
              .millisecondsSinceEpoch,
        }),
        isNull,
      );
      // Sin marca de tiempo no hay forma de saber si sigue vivo.
      expect(parse({'deviceId': 'pc_linux_1', 'isOnline': true}), isNull);
    });

    test('un heartbeat de 60 s sigue siendo válido (TTL de la nube)', () {
      final peer = InutilPlaybackSyncService.peerFromCloudDoc(
        {
          'deviceId': 'pc_linux_1',
          'isOnline': true,
          'lastSeenMs': now
              .subtract(const Duration(seconds: 60))
              .millisecondsSinceEpoch,
        },
        myDeviceId: 'phone_honor_1',
        now: now,
      );

      expect(peer, isNotNull);
      expect(peer!.isOnlineNow, isTrue);
    });
  });

  group('mergeConnectTargets', () {
    test('no duplica: la entrada LAN aporta la IP y la nube rellena lo que falta', () {
      final merged = InutilPlaybackSyncService.mergeConnectTargets(
        lanPeers: [
          lanPeer(deviceId: 'pc_linux_1', name: '', appVersion: ''),
        ],
        cloudPeers: [
          cloudPeer(
            deviceId: 'pc_linux_1',
            name: 'Torre de César',
            appVersion: '2.5.8+258',
          ),
        ],
      );

      expect(merged, hasLength(1));
      final peer = merged.single;
      expect(peer.ip, '192.168.100.24');
      expect(peer.isCloudOnly, isFalse);
      expect(peer.deviceName, 'Torre de César');
      expect(peer.appVersion, '2.5.8+258');
      expect(peer.isHost, isTrue);
    });

    test('los equipos que suenan van primero y cada dispositivo aparece una vez', () {
      final merged = InutilPlaybackSyncService.mergeConnectTargets(
        lanPeers: [
          lanPeer(deviceId: 'zz_phone', name: 'Zeta', isHost: false),
        ],
        cloudPeers: [
          cloudPeer(deviceId: 'aa_pc', name: 'Alpha'),
          cloudPeer(deviceId: 'bb_tablet', name: 'Beta', isHost: false),
        ],
      );

      expect(merged.map((p) => p.deviceId), ['aa_pc', 'bb_tablet', 'zz_phone']);
    });
  });

  group('pickAutoPairCandidate', () {
    test('prefiere el PC de la red local por encima de todo', () {
      final candidate = InutilPlaybackSyncService.pickAutoPairCandidate([
        lanPeer(deviceId: 'pc_lan'),
        cloudPeer(deviceId: 'pc_cloud'),
      ]);

      expect(candidate?.deviceId, 'pc_lan');
    });

    test('sin nada en la red local usa el PC que reporta la nube', () {
      final candidate = InutilPlaybackSyncService.pickAutoPairCandidate([
        cloudPeer(deviceId: 'tablet_cloud', isHost: false),
        cloudPeer(deviceId: 'pc_cloud'),
      ]);

      expect(candidate?.deviceId, 'pc_cloud');
    });

    test('un celular de la nube no se elige solo: hay que elegirlo a mano', () {
      final candidate = InutilPlaybackSyncService.pickAutoPairCandidate([
        cloudPeer(deviceId: 'tablet_cloud', isHost: false),
      ]);

      expect(candidate, isNull);
    });
  });

  group('cola de comandos en la nube', () {
    test('el id del comando es ordenable por tiempo y único por emisor', () {
      final a = InutilPlaybackSyncService.commandDocumentId(
        createdAtMs: 1763_000_000_000,
        targetDeviceId: 'pc_linux_abcdef0123',
        issuerDeviceId: 'phone_honor_1',
      );
      final b = InutilPlaybackSyncService.commandDocumentId(
        createdAtMs: 1763_000_000_001,
        targetDeviceId: 'pc_linux_abcdef0123',
        issuerDeviceId: 'phone_honor_1',
      );
      final c = InutilPlaybackSyncService.commandDocumentId(
        createdAtMs: 1763_000_000_000,
        targetDeviceId: 'pc_linux_abcdef0123',
        issuerDeviceId: 'phone_honor_1',
        nonce: 1,
      );

      expect(a, '1763000000000-pc_linux-phone_honor_1');
      expect(b.compareTo(a) > 0, isTrue);
      expect(c, isNot(a));
    });

    test('un documento fresco para este equipo se convierte en comando', () {
      final command = InutilPlaybackSyncService.cloudCommandFromDoc(
        {
          'commandId': '1763000000000-pc_linux-phone_honor_1',
          'target': 'pc_linux_abcdef0123',
          'type': 'playTrack',
          'issuer': 'phone_honor_1',
          'issuerName': 'Honor de César',
          'paramJson': '{"trackId":"t1","title":"Canción"}',
          'createdAtMs': now.millisecondsSinceEpoch,
          'deliveredAtMs': 0,
        },
        myDeviceId: 'pc_linux_abcdef0123',
        now: now,
      );

      expect(command, isNotNull);
      expect(command!.type, 'playTrack');
      expect(command.param, isA<Map<String, dynamic>>());
      expect((command.param as Map)['trackId'], 't1');
    });

    test('descarta comandos de otro equipo, ya entregados o caducados', () {
      Map<String, dynamic> base({String target = 'pc_linux_1'}) => {
            'commandId': 'cmd-1',
            'target': target,
            'type': 'pause',
            'createdAtMs': now.millisecondsSinceEpoch,
            'deliveredAtMs': 0,
          };

      CloudCommand? parse(Map<String, dynamic> doc, {DateTime? at}) =>
          InutilPlaybackSyncService.cloudCommandFromDoc(
            doc,
            myDeviceId: 'pc_linux_1',
            now: at ?? now,
          );

      expect(parse(base(target: 'otro_equipo')), isNull);
      expect(
        parse({...base(), 'deliveredAtMs': now.millisecondsSinceEpoch}),
        isNull,
      );
      expect(
        parse(
          base(),
          at: now.add(InutilPlaybackSyncService.commandTtl +
              const Duration(seconds: 1)),
        ),
        isNull,
      );
    });

    test('un comando enviado dos veces no se ejecuta dos veces', () {
      // El id se deriva del instante de envío, así que el puente heredado y la
      // cola de la nube comparten el mismo identificador.
      final id = InutilPlaybackSyncService.commandDocumentId(
        createdAtMs: 1763000000000,
        targetDeviceId: 'pc_linux_1',
        issuerDeviceId: 'phone_honor_1',
      );

      expect(
        InutilPlaybackSyncService.commandDocumentId(
          createdAtMs: 1763000000000,
          targetDeviceId: 'pc_linux_1',
          issuerDeviceId: 'phone_honor_1',
        ),
        id,
      );
    });
  });

  group('parámetros y versiones', () {
    test('decodeCloudParam tolera el texto plano de las versiones antiguas', () {
      expect(InutilPlaybackSyncService.decodeCloudParam(''), isNull);
      expect(InutilPlaybackSyncService.decodeCloudParam('pause'), 'pause');
      expect(InutilPlaybackSyncService.decodeCloudParam('{"a":1}'), {'a': 1});
      // `{'a': 1}.toString()` de Dart viejo: no es JSON, se devuelve tal cual.
      expect(InutilPlaybackSyncService.decodeCloudParam("{a: '1'}"), "{a: '1'}");
    });

    test('normalizeRemoteParam reconstruye el mapa venga en el formato que venga', () {
      expect(
        InutilPlaybackSyncService.normalizeRemoteParam('{"trackId":"t9"}'),
        {'trackId': 't9'},
      );
      expect(
        InutilPlaybackSyncService.normalizeRemoteParam({'trackId': 't9'}),
        {'trackId': 't9'},
      );
      expect(InutilPlaybackSyncService.normalizeRemoteParam(null), isNull);
    });

    test('el puente heredado sólo hace falta con apps anteriores a 2.5.8', () {
      expect(InutilPlaybackSyncService.needsLegacyCommandBridge(null), isTrue);
      expect(InutilPlaybackSyncService.needsLegacyCommandBridge(''), isTrue);
      expect(
        InutilPlaybackSyncService.needsLegacyCommandBridge('2.5.7+257'),
        isTrue,
      );
      expect(
        InutilPlaybackSyncService.needsLegacyCommandBridge('2.5.8+258'),
        isFalse,
      );
      expect(InutilPlaybackSyncService.needsLegacyCommandBridge('2.6.0'), isFalse);
      expect(InutilPlaybackSyncService.needsLegacyCommandBridge('2.6'), isFalse);
    });

    test('parseVersionNumber / compareVersionNumbers rellenan con ceros', () {
      expect(InutilPlaybackSyncService.parseVersionNumber('2.5.8+258'),
          [2, 5, 8]);
      expect(InutilPlaybackSyncService.parseVersionNumber('beta'), isNull);
      expect(
        InutilPlaybackSyncService.compareVersionNumbers([2, 5], [2, 5, 1]),
        -1,
      );
      expect(
        InutilPlaybackSyncService.compareVersionNumbers([2, 5, 8], [2, 5, 8]),
        0,
      );
    });
  });

  group('ventanas de vigencia', () {
    test('un peer de la red local caduca mucho antes que uno de la nube', () {
      final lanOld = lanPeer(
        deviceId: 'pc_lan',
        lastSeen: now.subtract(const Duration(seconds: 20)),
      );
      final cloudOld = cloudPeer(
        deviceId: 'pc_cloud',
        lastSeen: now.subtract(const Duration(seconds: 20)),
      );

      // 20 s sin anuncios UDP: ya no está en la red local...
      expect(
        InutilPlaybackSyncService.isPeerOnline(lanOld),
        isFalse,
      );
      // ...pero 20 s de heartbeat en la nube siguen siendo frescos.
      expect(cloudOld.isOnlineNow, isTrue);
    });
  });

  group('lógica de enrutamiento Spotify Connect (shouldRoutePlaybackToPeer)', () {
    test('cuando la PC ya es el altavoz activo, el cambio de canción se envía a la PC', () {
      final shouldRoute = InutilPlaybackSyncService.shouldRoutePlaybackToPeer(
        autoPlayOnPc: false, // aunque no esté activado autoPlayOnPc
        isCurrentDeviceActive: false, // el móvil NO es el altavoz activo (la PC lo es)
        remoteActiveDeviceId: 'pc_linux_1',
        hasTargetPeer: true,
        isDesktopHost: false, // es un móvil
        isPlaybackRouteSuppressed: false,
        forcePush: true,
        isPlaying: true,
      );

      expect(shouldRoute, isTrue);
    });

    test('con autoPlayOnPc activado, cualquier play se envía a la PC aunque el móvil fuera el activo', () {
      final shouldRoute = InutilPlaybackSyncService.shouldRoutePlaybackToPeer(
        autoPlayOnPc: true,
        isCurrentDeviceActive: true, // el móvil era el activo
        remoteActiveDeviceId: '',
        hasTargetPeer: true,
        isDesktopHost: false,
        isPlaybackRouteSuppressed: false,
        forcePush: true,
        isPlaying: true,
      );

      expect(shouldRoute, isTrue);
    });

    test('si el usuario transfirió explícitamente la reproducción al móvil, no se reenvía a la PC', () {
      final shouldRoute = InutilPlaybackSyncService.shouldRoutePlaybackToPeer(
        autoPlayOnPc: true,
        isCurrentDeviceActive: true,
        remoteActiveDeviceId: '',
        hasTargetPeer: true,
        isDesktopHost: false,
        isPlaybackRouteSuppressed: true, // supresión activa (ej. botón "Transferir aquí")
        forcePush: true,
        isPlaying: true,
      );

      expect(shouldRoute, isFalse);
    });

    test('un snapshot remoto (isRemoteSnapshot) nunca se reenvía a la PC para evitar bucles', () {
      final shouldRoute = InutilPlaybackSyncService.shouldRoutePlaybackToPeer(
        autoPlayOnPc: true,
        isCurrentDeviceActive: false,
        remoteActiveDeviceId: 'pc_linux_1',
        hasTargetPeer: true,
        isDesktopHost: false,
        isPlaybackRouteSuppressed: false,
        forcePush: true,
        isPlaying: true,
        isRemoteSnapshot: true,
      );

      expect(shouldRoute, isFalse);
    });

    test('en la PC (desktop host) nunca se reenvía a otro equipo (evita bucle)', () {
      final shouldRoute = InutilPlaybackSyncService.shouldRoutePlaybackToPeer(
        autoPlayOnPc: true,
        isCurrentDeviceActive: false,
        remoteActiveDeviceId: 'phone_1',
        hasTargetPeer: true,
        isDesktopHost: true, // es una PC
        isPlaybackRouteSuppressed: false,
        forcePush: true,
        isPlaying: true,
      );

      expect(shouldRoute, isFalse);
    });
  });
}

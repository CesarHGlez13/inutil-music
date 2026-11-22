import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../utils/release_paths.dart';
import 'firebase_auth_service.dart';
import 'firebase_config.dart';
import 'firebase_firestore_service.dart';

/// Dispositivo de la misma cuenta visible para el mando a distancia.
///
/// Puede conocerse por la red local (anuncio UDP + `GET /api/ping`) o por su
/// heartbeat en la nube (`users/{uid}/devices`). Un peer descubierto sólo en la
/// nube no tiene IP útil: sus comandos viajan por Firestore, igual que hace
/// Spotify Connect, y así funcionan aunque el PC esté en otra red o el
/// firewall bloquee los puertos LAN.
class LanDevicePeer {
  LanDevicePeer({
    required this.ip,
    required this.port,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    this.userEmail = '',
    this.uid = '',
    this.isHost = false,
    this.fromCloud = false,
    this.appVersion = '',
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  final String ip;
  final int port;
  final String deviceId;
  final String deviceName;
  final String platform;
  final String userEmail;
  final String uid;

  /// true en equipos de escritorio (suenan) frente a móviles (mandos).
  final bool isHost;

  /// true si este peer viene del registro en la nube, no de un anuncio LAN.
  final bool fromCloud;

  /// Versión de la app anunciada por el peer (puede venir vacía).
  final String appVersion;

  DateTime lastSeen;

  String get httpBaseUrl => 'http://$ip:$port';

  /// Sin IP útil: sólo se le puede hablar a través de Firestore.
  bool get isCloudOnly => ip.isEmpty;

  /// Ventana de vigencia según el canal que mantiene vivo al peer: los
  /// anuncios UDP llegan cada 2 s, el heartbeat en la nube cada 30 s.
  bool get isOnlineNow => fromCloud
      ? DateTime.now().difference(lastSeen) <
            InutilPlaybackSyncService.cloudPeerTtl
      : DateTime.now().difference(lastSeen) <
            InutilPlaybackSyncService.lanPeerTtl;

  /// Determina si el dispositivo pertenece al mismo usuario/cuenta.
  bool isSameAccount(String? myEmail, String? myUid) {
    if (userEmail.isNotEmpty && myEmail != null && myEmail.isNotEmpty) {
      if (userEmail.trim().toLowerCase() == myEmail.trim().toLowerCase()) {
        return true;
      }
    }
    if (uid.isNotEmpty && myUid != null && myUid.isNotEmpty) {
      if (uid.trim() == myUid.trim()) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'port': port,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'platform': platform,
    'userEmail': userEmail,
    'uid': uid,
    'isHost': isHost,
    'fromCloud': fromCloud,
    'appVersion': appVersion,
    'lastSeen': lastSeen.toUtc().toIso8601String(),
  };

  factory LanDevicePeer.fromJson(Map<String, dynamic> json) {
    return LanDevicePeer(
      ip: json['ip'] as String? ?? '127.0.0.1',
      port: json['port'] as int? ?? 52445,
      deviceId: json['deviceId'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? 'Inútil Device',
      platform: json['platform'] as String? ?? 'generic',
      userEmail: json['userEmail'] as String? ?? '',
      uid: json['uid'] as String? ?? '',
      isHost: json['isHost'] as bool? ?? false,
      fromCloud: json['fromCloud'] as bool? ?? false,
      appVersion: json['appVersion'] as String? ?? '',
      lastSeen:
          DateTime.tryParse(json['lastSeen']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// Modelo de sesión de reproducción compartida en tiempo real (Spotify Connect).
@immutable
class PlaybackSyncSession {
  const PlaybackSyncSession({
    required this.activeDeviceId,
    required this.activeDeviceName,
    required this.activeDevicePlatform,
    this.trackId = '',
    this.title = '',
    this.artist = '',
    this.album = '',
    this.thumbnailUrl = '',
    this.positionMs = 0,
    this.durationMs = 0,
    this.isPlaying = false,
    this.volume = 1.0,
    this.shuffleEnabled = false,
    this.repeatMode = 'off',
    this.queue = const <Map<String, dynamic>>[],
    this.queueIndex = 0,
    this.updatedAt,
    this.pendingCommandId = '',
    this.pendingCommandType = '',
    this.pendingCommandParam,
    this.pendingCommandIssuerId = '',
  });

  final String activeDeviceId;
  final String activeDeviceName;
  final String activeDevicePlatform;
  final String trackId;
  final String title;
  final String artist;
  final String album;
  final String thumbnailUrl;
  final int positionMs;
  final int durationMs;
  final bool isPlaying;
  final double volume;
  final bool shuffleEnabled;
  final String repeatMode;
  final List<Map<String, dynamic>> queue;
  final int queueIndex;
  final DateTime? updatedAt;
  final String pendingCommandId;
  final String pendingCommandType;
  final dynamic pendingCommandParam;
  final String pendingCommandIssuerId;

  /// Posición estimada **en el instante [now]**. Así se puede probar sin depender
  /// del reloj del equipo (el test usa un `now` fijo); ver
  /// test/core/firebase/playback_session_staleness_test.dart.
  int estimatedPositionMsAt(DateTime now) {
    final stamp = updatedAt;
    if (stamp == null || !isPlaying || durationMs <= 0) return positionMs;
    final elapsed = now.difference(stamp).inMilliseconds;
    if (elapsed <= 0) return positionMs;
    final advanced = positionMs + elapsed;
    return advanced > durationMs ? durationMs : advanced;
  }

  /// Posición estimada **en este instante** para el dispositivo que solo manda
  /// (el mando a distancia). El altavoz escribe la sesión cada ~8 s, así que
  /// entre escrituras hay que contar el tiempo transcurrido: sin esto la barra
  /// se queda congelada en el último refresco y parece "colgada sin avanzar".
  /// Se topa en la duración, nunca la rebasa.
  int get estimatedPositionMs => estimatedPositionMsAt(DateTime.now());

  PlaybackSyncSession copyWith({
    String? activeDeviceId,
    String? activeDeviceName,
    String? activeDevicePlatform,
    bool? isPlaying,
    int? positionMs,
    double? volume,
    bool? shuffleEnabled,
    String? repeatMode,
    List<Map<String, dynamic>>? queue,
    int? queueIndex,
    DateTime? updatedAt,
  }) {
    return PlaybackSyncSession(
      activeDeviceId: activeDeviceId ?? this.activeDeviceId,
      activeDeviceName: activeDeviceName ?? this.activeDeviceName,
      activeDevicePlatform: activeDevicePlatform ?? this.activeDevicePlatform,
      trackId: trackId,
      title: title,
      artist: artist,
      album: album,
      thumbnailUrl: thumbnailUrl,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs,
      isPlaying: isPlaying ?? this.isPlaying,
      volume: volume ?? this.volume,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      repeatMode: repeatMode ?? this.repeatMode,
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
      updatedAt: updatedAt ?? this.updatedAt,
      pendingCommandId: pendingCommandId,
      pendingCommandType: pendingCommandType,
      pendingCommandParam: pendingCommandParam,
      pendingCommandIssuerId: pendingCommandIssuerId,
    );
  }

  /// Payload ligero para Firestore (omite `queue` para mantener el documento
  /// pequeño y ahorrar cuota/ancho de banda en nube).
  Map<String, dynamic> toCloudJson() => {
    'activeDeviceId': activeDeviceId,
    'activeDeviceName': activeDeviceName,
    'activeDevicePlatform': activeDevicePlatform,
    'trackId': trackId,
    'title': title,
    'artist': artist,
    'album': album,
    'thumbnailUrl': thumbnailUrl,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'isPlaying': isPlaying,
    'volume': volume.clamp(0.0, 1.0),
    'shuffleEnabled': shuffleEnabled,
    'repeatMode': repeatMode,
    'queueIndex': queueIndex,
    'updatedAt': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    'pendingCommandId': pendingCommandId,
    'pendingCommandType': pendingCommandType,
    'pendingCommandParam': pendingCommandParam?.toString() ?? '',
    'pendingCommandIssuerId': pendingCommandIssuerId,
  };

  /// Payload completo para `/api/session` en LAN (incluye la cola compacta).
  Map<String, dynamic> toJson() => {
    ...toCloudJson(),
    if (queue.isNotEmpty) 'queue': queue,
  };

  factory PlaybackSyncSession.fromJson(Map<String, dynamic> map) {
    final rawQueue = map['queue'];
    final parsedQueue = <Map<String, dynamic>>[];
    if (rawQueue is List) {
      for (final item in rawQueue) {
        if (item is Map) {
          parsedQueue.add(Map<String, dynamic>.from(item));
        }
      }
    }
    final rawVolume = map['volume'];
    final parsedVolume = rawVolume is num
        ? rawVolume.toDouble().clamp(0.0, 1.0)
        : (double.tryParse(rawVolume?.toString() ?? '') ?? 1.0).clamp(0.0, 1.0);
    final rawRepeat = (map['repeatMode'] as String? ?? 'off').trim();
    return PlaybackSyncSession(
      activeDeviceId: map['activeDeviceId'] as String? ?? '',
      activeDeviceName:
          map['activeDeviceName'] as String? ?? 'Dispositivo Inútil',
      activeDevicePlatform: map['activeDevicePlatform'] as String? ?? 'generic',
      trackId: map['trackId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      artist: map['artist'] as String? ?? '',
      album: map['album'] as String? ?? '',
      thumbnailUrl: map['thumbnailUrl'] as String? ?? '',
      positionMs: map['positionMs'] is int
          ? map['positionMs'] as int
          : int.tryParse(map['positionMs']?.toString() ?? '') ?? 0,
      durationMs: map['durationMs'] is int
          ? map['durationMs'] as int
          : int.tryParse(map['durationMs']?.toString() ?? '') ?? 0,
      isPlaying: map['isPlaying'] as bool? ?? false,
      volume: parsedVolume,
      shuffleEnabled: map['shuffleEnabled'] as bool? ?? false,
      repeatMode: rawRepeat.isEmpty ? 'off' : rawRepeat,
      queue: parsedQueue,
      queueIndex: map['queueIndex'] is int
          ? map['queueIndex'] as int
          : int.tryParse(map['queueIndex']?.toString() ?? '') ?? 0,
      updatedAt: map['updatedAt'] is DateTime
          ? map['updatedAt'] as DateTime
          : DateTime.tryParse(map['updatedAt']?.toString() ?? ''),
      pendingCommandId: map['pendingCommandId'] as String? ?? '',
      pendingCommandType: map['pendingCommandType'] as String? ?? '',
      pendingCommandParam: map['pendingCommandParam'],
      pendingCommandIssuerId: map['pendingCommandIssuerId'] as String? ?? '',
    );
  }
}

/// Comando de reproducción en tránsito por la nube (`users/{uid}/commands`).
///
/// Es el equivalente al `POST /api/command` de la red local para equipos que no
/// comparten Wi-Fi: quien manda escribe el documento y el destino lo ejecuta al
/// leerlo, sin necesidad de puertos abiertos ni de la misma subred.
@immutable
class CloudCommand {
  const CloudCommand({
    required this.id,
    required this.type,
    required this.targetDeviceId,
    required this.issuerDeviceId,
    this.param,
    this.issuerName = '',
    this.createdAt,
  });

  final String id;
  final String type;
  final String targetDeviceId;
  final String issuerDeviceId;
  final dynamic param;
  final String issuerName;
  final DateTime? createdAt;

  Map<String, dynamic> toFirestoreDoc() => {
    'commandId': id,
    'target': targetDeviceId,
    'type': type,
    // El parámetro viaja como JSON para que un mapa anidado (playTrack) no se
    // deforme al atravesar la API REST de Firestore.
    'paramJson': param == null ? '' : jsonEncode(param),
    'issuer': issuerDeviceId,
    'issuerName': issuerName,
    'createdAtMs': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
    'deliveredAtMs': 0,
  };
}

/// Callback para ejecutar acciones en el reproductor local cuando llega un comando remoto.
typedef RemotePlaybackCommandHandler =
    Future<void> Function(String commandType, dynamic param);

/// Coordinador de Sincronización entre Android, Linux y Windows.
/// Soporta vinculación automática y transferencia de reproducción en red local (LAN)
/// y sincronización en la nube con Firestore.
class InutilPlaybackSyncService extends ChangeNotifier {
  InutilPlaybackSyncService._();
  static final InutilPlaybackSyncService instance =
      InutilPlaybackSyncService._();

  static const int _defaultPort = 52445;
  static const int _udpPort = 52446;
  static const String _autoPlayOnPcPrefKey = 'inutil_autoplay_on_pc';
  static const String _knownHostsPrefKey = 'inutil_known_lan_hosts';

  /// Un peer de la red local deja de considerarse "en línea" tras este tiempo
  /// sin verse (los anuncios UDP llegan cada 2 s).
  static const Duration lanPeerTtl = Duration(seconds: 12);

  /// Idem para los peers vistos sólo a través de la nube: su heartbeat
  /// (`users/{uid}/devices`) es más lento para no castigar la cuota de
  /// Firestore, así que la ventana de vigencia es mayor.
  static const Duration cloudPeerTtl = Duration(seconds: 90);

  /// Cada cuánto publica este equipo su presencia en `users/{uid}/devices`.
  static const Duration presenceInterval = Duration(seconds: 30);

  /// Sondeos de la nube: lista de dispositivos de la cuenta y cola de comandos.
  static const Duration devicesPollInterval = Duration(seconds: 15);
  static const Duration commandsPollInterval = Duration(seconds: 3);

  /// Tras enviar un comando por la nube se mira la cola más a menudo durante
  /// esta ventana, para que el play/pause remoto responda en menos de un
  /// segundo en lugar de esperar al sondeo lento.
  static const Duration commandsBurstInterval = Duration(milliseconds: 700);
  static const Duration commandsBurstWindow = Duration(seconds: 8);

  /// Un comando que nadie ejecuta (el destino estaba apagado) se descarta.
  static const Duration commandTtl = Duration(minutes: 10);

  /// Subcolecciones bajo `users/{uid}/` que usa el relay en la nube. Las dos
  /// quedan dentro de la regla `match /users/{userId}/{sub}/{item}` del
  /// proyecto, que ya autoriza a leer y escribir al propio usuario.
  static const String devicesCollection = 'devices';
  static const String commandsCollection = 'commands';

  /// Ventana en la que no reenviamos la reproducción a otro dispositivo
  /// después de ejecutar un comando remoto (evita el bucle PC <-> móvil).
  static const Duration _routeSuppression = Duration(seconds: 6);

  /// Ventana en la que esperamos a que el altavoz remoto confirme la canción
  /// que acabamos de transferirle. Resolver el stream puede tardar varios
  /// segundos; mientras tanto el documento de la nube todavía describe la
  /// canción anterior y no debe pisar la sesión optimista del mando.
  static const Duration remoteHandoverGrace = Duration(seconds: 20);

  /// Ventana tras la cual un estado que sigue diciendo `isPlaying` pero dejó de
  /// refrescarse es un **fantasma**: el altavoz ya no escribe (cerró la app, se
  /// le cayó la red o su escritura no pasó por el relay). Mostrarlo como
  /// reproducción en curso deja el mando colgado fingiendo que suena — el bug
  /// medido: sesión congelada 28 min en `positionMs` 5611/186161.
  static const Duration sessionStaleAfter = Duration(seconds: 20);

  /// Ventana durante la cual un dispositivo que acaba de ceder la reproducción
  /// a otro **no** se declara altavoz activo, aunque pierda de vista al par.
  /// Sin esto un mando silencioso se cree el que suena y pisa el documento de
  /// la nube con su snapshot congelado (`isCurrentDeviceActive` era true solo
  /// porque `_currentRemoteSession` se había vacío).
  static const Duration handoffAuthorityGrace = Duration(seconds: 45);

  final InutilAuthService _auth = InutilAuthService.instance;
  final InutilFirestoreService _firestore = InutilFirestoreService.instance;

  HttpServer? _lanHttpServer;
  RawDatagramSocket? _udpBroadcastSocket;
  RawDatagramSocket? _udpSocket;
  int _currentLanPort = _defaultPort;

  PlaybackSyncSession? _currentLocalSession;
  PlaybackSyncSession? _currentRemoteSession;

  /// Equipo al que acabamos de ceder la reproducción y hasta cuándo seguimos
  /// creyendo que es él quien suena, aunque perdamos su sesión de vista (LAN
  /// barrida, firewall, presencia caducada). Es lo que evita que un mando
  /// silencioso se declare altavoz activo y congele la pantalla.
  String _handedOffDeviceId = '';
  String _handedOffDeviceName = '';
  DateTime _handedOffUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Canción transferida a un altavoz remoto que aún no la ha confirmado, y
  /// instante hasta el cual seguimos esperando su confirmación.
  String? _remoteHandoverTrackId;
  DateTime _remoteHandoverUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _syncPollingTimer;
  Timer? _lanDiscoveryTimer;
  Timer? _lanSessionTimer;
  DateTime _lastCloudSessionPoll = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _optimisticControlGuardUntil = DateTime.fromMillisecondsSinceEpoch(
    0,
  );
  String? _lastPlayTrackDedupKey;
  DateTime _lastPlayTrackDedupAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Última re-sonda del relay dentro del tick de 3 s, para no gastar
  /// handshakes TCP en cada tick.
  DateTime _lastRelayReprobe = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _relayReprobeInterval = Duration(seconds: 45);
  int _cloudPollFailures = 0;
  DateTime _cloudPollBlockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPositionPushTime = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastProcessedCommandId = '';
  RemotePlaybackCommandHandler? onRemoteCommandReceived;

  final Map<String, LanDevicePeer> _discoveredPeers = {};

  /// Dispositivos de la cuenta vistos en `users/{uid}/devices` (puede que no
  /// estén en esta red local, o que el firewall bloquee sus puertos).
  final Map<String, LanDevicePeer> _cloudDevices = {};

  /// Comandos de la nube ya ejecutados o descartados en esta ejecución de la
  /// app: evita repetir un `playTrack` si el sondeo vuelve a ver el documento.
  final Set<String> _processedCommandIds = {};

  LanDevicePeer? _autoPairedPeer;
  bool _autoPlayOnPc = false;

  Timer? _presenceTimer;
  Timer? _cloudDevicesTimer;
  Timer? _cloudCommandsTimer;
  int _lastPresencePushMs = 0;
  DateTime _commandsBurstUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Hosts (anunciados por UDP o recordados de sesiones anteriores) que ya
  /// respondieron a /api/ping: no hace falta volver a barrerlos cada 3 s.
  final Set<String> _liveHosts = {};
  Timer? _udpAnnounceTimer;
  DateTime _lastSubnetSweep = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _routeSuppressedUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Lo que este dispositivo debe **mostrar** como "suena ahora": la sesión del
  /// altavoz si la tenemos y, si no, la nuestra — pero solo mientras siga
  /// fresca. [visibleSession] es lo que impide que un snapshot viejo que
  /// todavía dice `isPlaying` siga fingiendo reproducción en curso.
  PlaybackSyncSession? get remoteSession => visibleSession(
    remote: _currentRemoteSession,
    local: _currentLocalSession,
    now: DateTime.now(),
  );

  LanDevicePeer? get autoPairedPeer => _autoPairedPeer;
  List<LanDevicePeer> get discoveredPeers =>
      _discoveredPeers.values.where(isPeerOnline).toList();

  /// Todos los destinos posibles del mando a distancia: los equipos de la red
  /// local y los que sólo se ven por Firestore, deduplicados y ordenados
  /// (primero los que suenan). Así la lista funciona sin abrir puertos y
  /// aunque el móvil esté conectado por datos y no por Wi-Fi.
  List<LanDevicePeer> get connectTargets => mergeConnectTargets(
    lanPeers: _discoveredPeers.values.where(isPeerOnline),
    cloudPeers: _cloudDevices.values.where((peer) => peer.isOnlineNow),
  );

  bool get autoPlayOnPc => _autoPlayOnPc;
  int get currentLanPort => _currentLanPort;

  /// true si este dispositivo debe comportarse como "sumidero" de audio
  /// (escritorio) en lugar de como control remoto (móvil/tablet).
  static bool get isDesktopHost =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  /// true si acabamos de ejecutar un comando remoto: nuestra reproducción
  /// local es "heredada" y no debe reenviarse a otro dispositivo.
  bool get isPlaybackRouteSuppressed =>
      DateTime.now().isBefore(_routeSuppressedUntil);

  static bool isPeerOnline(LanDevicePeer peer) =>
      DateTime.now().difference(peer.lastSeen) < lanPeerTtl;

  // ---------------------------------------------------------------------------
  // Helpers puros del relay en la nube (sin red: los cubren los tests).
  // ---------------------------------------------------------------------------

  /// Une las vistas LAN y nube sin duplicar dispositivos.
  ///
  /// Si un mismo `deviceId` se vio por ambos canales manda la entrada LAN, que
  /// trae la IP y el puerto reales para comandar al instante; la nube sólo
  /// rellena lo que la LAN no sepa (nombre, versión, si el equipo es de
  /// escritorio). El orden prioriza los equipos que suenan.
  @visibleForTesting
  static List<LanDevicePeer> mergeConnectTargets({
    required Iterable<LanDevicePeer> lanPeers,
    required Iterable<LanDevicePeer> cloudPeers,
  }) {
    final byId = <String, LanDevicePeer>{};
    for (final peer in cloudPeers) {
      if (peer.deviceId.isEmpty) continue;
      byId[peer.deviceId] = peer;
    }
    for (final peer in lanPeers) {
      if (peer.deviceId.isEmpty) continue;
      final cloud = byId[peer.deviceId];
      if (cloud == null) {
        byId[peer.deviceId] = peer;
        continue;
      }
      byId[peer.deviceId] = LanDevicePeer(
        ip: peer.ip,
        port: peer.port,
        deviceId: peer.deviceId,
        deviceName: peer.deviceName.isNotEmpty
            ? peer.deviceName
            : cloud.deviceName,
        platform: peer.platform.isNotEmpty ? peer.platform : cloud.platform,
        userEmail: peer.userEmail,
        uid: peer.uid,
        isHost: peer.isHost || cloud.isHost,
        fromCloud: false,
        appVersion: peer.appVersion.isNotEmpty
            ? peer.appVersion
            : cloud.appVersion,
        lastSeen: peer.lastSeen.isAfter(cloud.lastSeen)
            ? peer.lastSeen
            : cloud.lastSeen,
      );
    }

    final merged = byId.values.toList(growable: false)
      ..sort((a, b) {
        if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
        final byName = a.deviceName.compareTo(b.deviceName);
        return byName != 0 ? byName : a.deviceId.compareTo(b.deviceId);
      });
    return merged;
  }

  /// Convierte un documento `users/{uid}/devices/{deviceId}` en un peer en
  /// línea, o `null` si es este mismo equipo, está marcado como apagado o su
  /// heartbeat caducó.
  @visibleForTesting
  static LanDevicePeer? peerFromCloudDoc(
    Map<String, dynamic> doc, {
    required String myDeviceId,
    required DateTime now,
  }) {
    final deviceId = (doc['deviceId'] ?? '').toString();
    if (deviceId.isEmpty || deviceId == myDeviceId) return null;
    if (doc['isOnline'] == false) return null;

    final lastSeen =
        _millisToDateTime(doc['lastSeenMs']) ??
        _millisToDateTime(doc['updatedAt']);
    if (lastSeen == null) return null;
    final age = now.difference(lastSeen);
    if (age.isNegative || age > cloudPeerTtl) return null;

    final lanPort = doc['lanPort'] is int
        ? doc['lanPort'] as int
        : int.tryParse(doc['lanPort']?.toString() ?? '') ?? 0;

    return LanDevicePeer(
      // La IP local se ignora a propósito: puede ser de otra red y no hay forma
      // de comprobarla sin esperar un timeout. Los comandos viajan por
      // Firestore hasta que un anuncio UDP confirme que sí es alcanzable.
      ip: '',
      port: lanPort,
      deviceId: deviceId,
      deviceName: (doc['name'] ?? 'Dispositivo Inútil').toString(),
      platform: (doc['platform'] ?? 'generic').toString(),
      isHost: doc['isHost'] as bool? ?? false,
      fromCloud: true,
      appVersion: (doc['appVersion'] ?? '').toString(),
      lastSeen: lastSeen,
    );
  }

  /// Extrae un endpoint LAN privado (`192.168.*`, `10.*`, `172.16-31.*`)
  /// anunciado en el documento `users/{uid}/devices/{deviceId}` para intentar
  /// enlace directo por Wi-Fi (sin esperar UDP broadcast, que Android suele
  /// descartar en ahorro de batería).
  @visibleForTesting
  static ({String ip, int port})? extractProbeableLanEndpoint(
    Map<String, dynamic> doc,
  ) {
    final ip = (doc['lanIp'] ?? '').toString().trim();
    final port = doc['lanPort'] is int
        ? doc['lanPort'] as int
        : int.tryParse(doc['lanPort']?.toString() ?? '') ?? 0;
    if (ip.isEmpty || port <= 0 || port > 65535) return null;
    if (!_isPrivateLanIpv4(ip)) return null;
    return (ip: ip, port: port);
  }

  static bool _isPrivateLanIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
      octets.add(n);
    }
    if (octets[0] == 10) return true;
    if (octets[0] == 192 && octets[1] == 168) return true;
    if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return true;
    return false;
  }

  /// Nombre del altavoz remoto a mostrar en verde en el reproductor / mini
  /// player: sólo se muestra cuando OTRO dispositivo está sonando actualmente,
  /// nunca cuando el audio suena localmente (comportamiento Spotify Connect).
  @visibleForTesting
  static String? remoteSpeakerBadgeName({
    required bool isCurrentDeviceActive,
    required String remoteActiveDeviceName,
  }) {
    if (isCurrentDeviceActive) return null;
    final trimmed = remoteActiveDeviceName.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Nombre del altavoz remoto activo ahora mismo (`null` si suena aquí).
  String? get activeRemoteSpeakerName => remoteSpeakerBadgeName(
    isCurrentDeviceActive: isCurrentDeviceActive,
    remoteActiveDeviceName: activeDeviceDisplayName,
  );

  /// `true` cuando existe al menos un destino Connect en línea (LAN o nube).
  bool get hasConnectTarget =>
      _autoPairedPeer != null || connectTargets.isNotEmpty;

  /// Candidato a vincularse automáticamente: un PC de la red local tiene
  /// preferencia (responde al instante); si no hay ninguno se usa el equipo de
  /// escritorio que la nube reporta en línea. Un móvil en la nube no se elige
  /// solo: ahí el usuario decide el altavoz desde el panel.
  @visibleForTesting
  static LanDevicePeer? pickAutoPairCandidate(List<LanDevicePeer> targets) {
    if (targets.isEmpty) return null;
    for (final peer in targets) {
      if (!peer.isCloudOnly && peer.isHost) return peer;
    }
    for (final peer in targets) {
      if (!peer.isCloudOnly) return peer;
    }
    for (final peer in targets) {
      if (peer.isHost) return peer;
    }
    return null;
  }

  /// Determina si un cambio de pista en el móvil debe enviarse al altavoz remoto
  /// (PC) en lugar de sonar localmente (lógica Spotify Connect).
  static bool shouldRoutePlaybackToPeer({
    required bool autoPlayOnPc,
    required bool isCurrentDeviceActive,
    required String remoteActiveDeviceId,
    required bool hasTargetPeer,
    required bool isDesktopHost,
    required bool isPlaybackRouteSuppressed,
    required bool forcePush,
    required bool isPlaying,
    bool isRemoteSnapshot = false,
  }) {
    if (isDesktopHost) return false;
    if (isRemoteSnapshot) return false;
    if (isPlaybackRouteSuppressed) return false;
    if (!forcePush || !isPlaying) return false;
    if (!hasTargetPeer) return false;

    final isRemoteSpeakerActive =
        !isCurrentDeviceActive && remoteActiveDeviceId.isNotEmpty;
    return autoPlayOnPc || isRemoteSpeakerActive;
  }

  /// Id de documento para un comando: ordenable por tiempo y único aunque dos
  /// equipos envíen el mismo milisegundo.
  @visibleForTesting
  static String commandDocumentId({
    required int createdAtMs,
    required String targetDeviceId,
    required String issuerDeviceId,
    int nonce = 0,
  }) {
    final targetShort = targetDeviceId.length <= 8
        ? targetDeviceId
        : targetDeviceId.substring(0, 8);
    final noncePart = nonce > 0 ? '-$nonce' : '';
    return '$createdAtMs-$targetShort-$issuerDeviceId$noncePart';
  }

  /// Documento `users/{uid}/commands/{id}` -> comando para este dispositivo.
  /// Devuelve `null` si es para otro equipo, ya fue entregado o caducó.
  @visibleForTesting
  static CloudCommand? cloudCommandFromDoc(
    Map<String, dynamic> doc, {
    required String myDeviceId,
    required DateTime now,
  }) {
    final target = (doc['target'] ?? '').toString();
    if (target.isNotEmpty && target != myDeviceId) return null;

    final id = (doc['commandId'] ?? doc['docId'] ?? '').toString();
    if (id.isEmpty) return null;

    final deliveredMs = _millisToDateTime(doc['deliveredAtMs']);
    if (deliveredMs != null) return null;

    final createdAt = _millisToDateTime(doc['createdAtMs']);
    if (createdAt == null) return null;
    if (now.difference(createdAt) > commandTtl) return null;

    final paramJson = (doc['paramJson'] ?? '').toString();
    return CloudCommand(
      id: id,
      type: (doc['type'] ?? '').toString(),
      targetDeviceId: target,
      issuerDeviceId: (doc['issuer'] ?? '').toString(),
      issuerName: (doc['issuerName'] ?? '').toString(),
      param: paramJson.isEmpty ? null : decodeCloudParam(paramJson),
      createdAt: createdAt,
    );
  }

  /// Decodifica el parámetro de un comando guardado como JSON.
  @visibleForTesting
  static dynamic decodeCloudParam(String raw) {
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
      return decoded;
    } catch (_) {
      // Versiones anteriores escribían `param.toString()`, que no es JSON.
      return raw;
    }
  }

  /// Da forma al parámetro recibido por cualquier canal (LAN, documento de
  /// sesión heredado o cola en la nube) antes de dárselo al reproductor.
  @visibleForTesting
  static dynamic normalizeRemoteParam(dynamic param) {
    if (param is Map<String, dynamic>) return param;
    if (param is Map) {
      return param.map((key, value) => MapEntry(key.toString(), value));
    }
    if (param is String && param.trim().isNotEmpty) {
      final decoded = decodeCloudParam(param);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    return param;
  }

  /// true si el destino aún no entiende la cola de comandos en la nube y hay
  /// que dejarle también el `pendingCommand*` en el documento de sesión.
  ///
  /// Con la versión desconocida se asume «antigua» a propósito: un peer que no
  /// anuncia `appVersion` viene de una 2.5.7 o anterior, y si no le dejamos el
  /// puente heredado se queda sin comandos. El doble envío no repite la orden
  /// porque ambos canales comparten el mismo id y se descarta el duplicado.
  @visibleForTesting
  static bool needsLegacyCommandBridge(String? peerAppVersion) {
    final version = peerAppVersion?.trim() ?? '';
    if (version.isEmpty) return true;
    final parsed = parseVersionNumber(version);
    if (parsed == null) return true;
    return compareVersionNumbers(parsed, const <int>[2, 5, 8]) < 0;
  }

  /// `2.5.8+258` o `2.5.8` -> `[2, 5, 8]`; `null` si no se interpreta.
  @visibleForTesting
  static List<int>? parseVersionNumber(String version) {
    final core = version.split('+').first.trim();
    if (core.isEmpty) return null;
    final parts = core.split('.');
    final numbers = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part.trim());
      if (value == null) return null;
      numbers.add(value);
    }
    return numbers.isEmpty ? null : numbers;
  }

  /// Comparación numérica de versiones, rellenando con ceros (`2.5` < `2.5.1`).
  @visibleForTesting
  static int compareVersionNumbers(List<int> a, List<int> b) {
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left < right ? -1 : 1;
    }
    return 0;
  }

  /// Recuerda un comando ya tramitado para no ejecutarlo dos veces (llega por
  /// la cola de la nube y por el documento de sesión heredado a la vez). El
  /// conjunto se recorta para que un PC encendido días no acumule ids.
  void _rememberProcessedCommand(String id) {
    if (id.isEmpty) return;
    if (_processedCommandIds.length > 200) _processedCommandIds.clear();
    _processedCommandIds.add(id);
  }

  /// Acepta milisegundos (int o string) y marcas de tiempo de Firestore.
  static DateTime? _millisToDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) {
      return value <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(value);
    }
    final asInt = int.tryParse(value.toString());
    if (asInt != null && asInt > 0) {
      return DateTime.fromMillisecondsSinceEpoch(asInt);
    }
    return DateTime.tryParse(value.toString());
  }

  /// Registra la canción que acabamos de transferir a un altavoz remoto para
  /// que su confirmación espere: el mando muestra la nueva canción desde ya.
  void _beginRemoteHandover(String trackId) {
    if (trackId.isEmpty) return;
    _remoteHandoverTrackId = trackId;
    _remoteHandoverUntil = DateTime.now().add(remoteHandoverGrace);
    // Desde ya somos el mando, no el altavoz: si perdemos de vista al par no
    // debemos declararnos activos y pisar su sesión con la nuestra.
    _markHandoffToPeer();
  }

  /// Cierra la espera cuando el altavoz (por LAN o por la nube) reporta justo
  /// la canción transferida.
  void _confirmRemoteHandover(String trackId) {
    final expected = _remoteHandoverTrackId;
    if (expected != null && expected == trackId) {
      _remoteHandoverTrackId = null;
    }
  }

  /// true mientras la transferencia a un altavoz remoto sigue en el aire: el
  /// documento de la nube, que todavía describe la canción anterior, no debe
  /// pisar la sesión optimista (el mando volvería a mostrar la canción vieja).
  bool _isAwaitingRemoteHandover(PlaybackSyncSession doc) {
    final expected = _remoteHandoverTrackId;
    if (expected == null) return false;
    if (doc.trackId == expected && doc.isPlaying) {
      _remoteHandoverTrackId = null;
      return false;
    }
    if (!DateTime.now().isBefore(_remoteHandoverUntil)) {
      // El altavoz nunca llegó a la canción (apagado, sin red o la perdió por
      // el camino): ya no hay nada que esperar, manda lo que reporte la nube.
      _remoteHandoverTrackId = null;
      return false;
    }
    return true;
  }

  // ── Política de "¿qué está sonando de verdad?" ─────────────────────────────
  // Todo el estado sincronizado se apoya en `updatedAt`: si el altavoz dejó de
  // escribir, el dato por bueno ya no describe la realidad, por muy
  // "reproduciendo" que diga. Estas funciones puras son las que deciden y están
  // cubiertas por test/core/firebase/playback_session_staleness_test.dart.

  /// true si [s] dice estar reproduciendo pero nadie lo refresca desde hace más
  /// de [sessionStaleAfter].
  static bool sessionIsGhost(PlaybackSyncSession s, {required DateTime now}) {
    final stamp = s.updatedAt;
    if (!s.isPlaying || stamp == null) return false;
    return now.difference(stamp) > sessionStaleAfter;
  }

  /// Sesión que el dispositivo debe mostrar: manda la del altavoz ([remote]);
  /// si no la hay, la local ([local]). Cualquiera que diga `isPlaying` sin
  /// refrescarse se marca **terminada**: es la única forma de que el mando se
  /// descoloque y la cola pueda avanzar.
  static PlaybackSyncSession? visibleSession({
    required PlaybackSyncSession? remote,
    required PlaybackSyncSession? local,
    required DateTime now,
  }) {
    final candidate = remote ?? local;
    if (candidate == null || candidate.trackId.isEmpty) return null;
    if (!sessionIsGhost(candidate, now: now)) return candidate;
    final end = candidate.durationMs > 0
        ? candidate.durationMs
        : candidate.positionMs;
    return candidate.copyWith(isPlaying: false, positionMs: end);
  }

  /// true si el altavoz que [session] declara sigue existiendo: aparece en la
  /// presencia viva ([liveDeviceIds]), es este mismo equipo, o no hay sesión
  /// remota que nombrar. Un id que ya no escribe presencia es un **fantasma**
  /// (el equipo se apagó, cambió de `deviceId` al reinstalar, o nos lo reenvió
  /// otro mando que tampoco lo ve), y mientras lo creyéramos nos dejaría de
  /// mando para siempre: la reproducción local se congela porque solo el
  /// altavoz escribe la sesión en la nube.
  static bool declaredSpeakerIsLive({
    required PlaybackSyncSession? session,
    required String myDeviceId,
    required Set<String> liveDeviceIds,
  }) {
    if (session == null) return true;
    final speaker = session.activeDeviceId;
    if (speaker.isEmpty || speaker == myDeviceId) return true;
    return liveDeviceIds.contains(speaker);
  }

  /// true si [deviceId] es el altavoz. Un mando que acaba de ceder la
  /// reproducción ([awaitingRemoteSpeaker]) NO lo es aunque pierda de vista al
  /// par; eso es lo que evita que se declare activo y congele la pantalla.
  /// Pero si el altavoz nombrado ya no existe ([speakerIsLive] = false) y
  /// además no estamos esperando a nadie, recuperar el audio local es lo
  /// correcto: no hay nadie sonando de verdad al otro lado.
  static bool deviceIsCurrentSpeaker({
    required PlaybackSyncSession? remote,
    required String deviceId,
    required bool awaitingRemoteSpeaker,
    bool speakerIsLive = true,
  }) {
    if (remote != null) {
      if (remote.activeDeviceId == deviceId) return true;
      if (!speakerIsLive && !awaitingRemoteSpeaker) return true;
      return false;
    }
    return !awaitingRemoteSpeaker;
  }

  /// true si el documento de la nube [doc] debe reemplazar lo guardado
  /// ([stored]). Compara con `>=` y no con `>`: un documento que vuelve a
  /// igualar el stamp ya guardado tiene que re-adoptarse, si no el mando se
  /// queda colgado en el último valor para siempre.
  static bool shouldAdoptDocument({
    required PlaybackSyncSession? stored,
    required PlaybackSyncSession doc,
  }) {
    if (stored == null) return true;
    final stamp = doc.updatedAt;
    if (stamp == null) return false;
    final old = stored.updatedAt;
    if (old == null) return true;
    return !stamp.isBefore(old);
  }

  /// Registra que acabamos de pasarle la reproducción a otro equipo: durante
  /// [handoffAuthorityGrace] no nos declaramos altavoz, aunque perdamos de
  /// vista al par (LAN barrida por el firewall, presencia caducada, etc.).
  void _markHandoffToPeer({String? deviceId, String? deviceName}) {
    final peer = _autoPairedPeer;
    final id = deviceId ?? peer?.deviceId ?? '';
    if (id.isEmpty || id == _auth.deviceId) return;
    _handedOffDeviceId = id;
    _handedOffDeviceName = deviceName ?? peer?.deviceName ?? '';
    _handedOffUntil = DateTime.now().add(handoffAuthorityGrace);
  }

  /// Este dispositivo sigue creyendo que otro es el altavoz: cedió hace menos
  /// de [handoffAuthorityGrace] y sigue a la espera de que lo confirme.
  bool get _awaitingRemoteSpeaker =>
      _handedOffDeviceId.isNotEmpty &&
      _handedOffDeviceId != _auth.deviceId &&
      DateTime.now().isBefore(_handedOffUntil);

  /// Conjunto de `deviceId` que **de verdad** están presentes ahora mismo: los
  /// documentos de `users/{uid}/devices` que no caducaron (ya filtrados por
  /// `cloudPeerTtl` al construir el peer), los pares de LAN que respondieron
  /// (`lanPeerTtl`) y el par con el que estamos vinculados. Es la lista contra
  /// la que se valida el `activeDeviceId` de la sesión compartida, igual que
  /// Spotify solo muestra en su panel de Connect los dispositivos que están
  /// mandando heartbeat.
  Set<String> _liveSpeakerIds() {
    final ids = <String>{};
    for (final peer in _cloudDevices.values) {
      if (peer.isOnlineNow && peer.deviceId.isNotEmpty) ids.add(peer.deviceId);
    }
    for (final peer in _discoveredPeers.values) {
      if (isPeerOnline(peer) && peer.deviceId.isNotEmpty) {
        ids.add(peer.deviceId);
      }
    }
    final paired = _autoPairedPeer;
    if (paired != null && paired.deviceId.isNotEmpty) ids.add(paired.deviceId);
    if (_handedOffDeviceId.isNotEmpty) ids.add(_handedOffDeviceId);
    return ids;
  }

  /// Ya no hay nadie al otro lado a quien esperar: este dispositivo recupera el
  /// control de su propio audio (lo usa el usuario al pulsar "activar").
  void _clearHandoffAuthority() {
    _handedOffDeviceId = '';
    _handedOffDeviceName = '';
    _handedOffUntil = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Si este dispositivo es el que actualmente reproduce el audio físicamente.
  bool get isCurrentDeviceActive => deviceIsCurrentSpeaker(
    remote: _currentRemoteSession,
    deviceId: _auth.deviceId,
    awaitingRemoteSpeaker: _awaitingRemoteSpeaker,
    speakerIsLive: declaredSpeakerIsLive(
      session: _currentRemoteSession,
      myDeviceId: _auth.deviceId,
      liveDeviceIds: _liveSpeakerIds(),
    ),
  );

  String get activeDeviceDisplayName {
    if (_currentRemoteSession != null) {
      return _currentRemoteSession!.activeDeviceName;
    }
    if (_awaitingRemoteSpeaker && _handedOffDeviceName.isNotEmpty) {
      return _handedOffDeviceName;
    }
    return _auth.deviceName;
  }

  /// Intervalo de sondeo en la nube para `playback_session/current`.
  ///
  /// * Con **un solo equipo en línea** (sin otro dispositivo con el que hacer
  ///   Connect) sondear cada 3 s quema ~1,200 req/h en el Worker y Firestore
  ///   sin ningún par al otro lado: baja a **30 s**.
  /// * Con enlace **LAN directo** (`:52445`) ya activo, baja a **15 s**.
  /// * Con un par remoto **sólo nube** (ej. 4G ↔ PC) mantiene **3 s**.
  @visibleForTesting
  static Duration cloudSessionPollInterval({
    required bool activeOnLan,
    required bool isCurrentDeviceActive,
    required bool hasAnyLanPeer,
    required bool hasAnyOnlinePeer,
  }) {
    if (isCurrentDeviceActive && !hasAnyOnlinePeer) {
      return const Duration(seconds: 30);
    }
    if (activeOnLan || (isCurrentDeviceActive && hasAnyLanPeer)) {
      return const Duration(seconds: 15);
    }
    return const Duration(seconds: 3);
  }

  /// Intervalo de sondeo en la nube para la cola `users/{uid}/commands`.
  @visibleForTesting
  static Duration cloudCommandPollInterval({
    required bool burst,
    required bool hasCloudOnlyPeer,
    required bool hasAnyLanPeer,
    required bool hasAnyOnlinePeer,
  }) {
    if (burst) return commandsBurstInterval;
    if (hasCloudOnlyPeer) return commandsPollInterval;
    if (hasAnyLanPeer || !hasAnyOnlinePeer) {
      return const Duration(seconds: 30);
    }
    return const Duration(seconds: 15);
  }

  /// Inicia el servidor LAN y la sincronización automática.
  void startSync() {
    _loadPreferences();
    _startLanServer();
    _startUdpAnnouncer();
    _startLanDiscovery();
    _startCloudRelay();

    _syncPollingTimer?.cancel();
    _syncPollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _maybeReprobeRelay();
      final now = DateTime.now();
      final activeRemoteId = _currentRemoteSession?.activeDeviceId ?? '';
      final activeOnLan =
          activeRemoteId.isNotEmpty &&
          activeRemoteId != _auth.deviceId &&
          _discoveredPeers[activeRemoteId] != null &&
          isPeerOnline(_discoveredPeers[activeRemoteId]!);
      final hasAnyLanPeer = _discoveredPeers.values.any(isPeerOnline);
      final hasAnyOnlinePeer = connectTargets.isNotEmpty;
      final minInterval = cloudSessionPollInterval(
        activeOnLan: activeOnLan,
        isCurrentDeviceActive: isCurrentDeviceActive,
        hasAnyLanPeer: hasAnyLanPeer,
        hasAnyOnlinePeer: hasAnyOnlinePeer,
      );
      if (minInterval > const Duration(seconds: 3) &&
          now.difference(_lastCloudSessionPoll) < minInterval) {
        return;
      }
      _lastCloudSessionPoll = now;
      _pollPlaybackSession();
    });
    _lanSessionTimer?.cancel();
    _lanSessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _pollActiveLanPeerSession();
    });
    _lastCloudSessionPoll = DateTime.now();
    _pollPlaybackSession();
  }

  void _pollActiveLanPeerSession() {
    if (isCurrentDeviceActive) return;
    final activeId = _currentRemoteSession?.activeDeviceId ?? '';
    LanDevicePeer? lanPeer = activeId.isNotEmpty
        ? _discoveredPeers[activeId]
        : null;
    if (lanPeer == null &&
        _autoPairedPeer != null &&
        !_autoPairedPeer!.isCloudOnly) {
      lanPeer = _autoPairedPeer;
    }
    if (lanPeer == null || lanPeer.isCloudOnly || !isPeerOnline(lanPeer)) {
      return;
    }
    unawaited(_fetchSessionFromPeer(lanPeer));
  }

  /// Re-sonda del relay del S7, colgada del tick de 3 s que ya existe.
  ///
  /// El problema que cierra: [FirebaseConfig.markRelayUnreachable] latchea
  /// Google para TODA la sesión. Si se reinicia `relay.py` (o el S7, o el
  /// WiFi) con la app abierta, las lecturas regresan a Firebase real y
  /// siguen pagando cuota de `users/{uid}/...` hasta que el usuario cierre y
  /// vuelva a abrir la app. Medido el 2026-11-20 justo después de reiniciar
  /// el relay: 0 peticiones de las apps al relay en 3 minutos, mientras los
  /// heartbeat de `users/{uid}/devices/*` aparecían escritos DIRECTO en Google
  /// con su `updatedAt` en el mismo segundo en que Google los recibía.
  ///
  /// Va aquí y no en un `Timer` nuevo porque el tick de 3 s ya existe y ya
  /// corre solo cuando hay sesión activa: no añade timers que queden pendientes
  /// en las pruebas de arranque. Y sondea sólo cuando
  /// [FirebaseConfig.relayRecoveryWorthy] (host horneado + declarado caído +
  /// este equipo sí tuvo relación con el relay), a lo sumo una vez cada
  /// [_relayReprobeInterval] para no gastar handshakes.
  void _maybeReprobeRelay() {
    if (!FirebaseConfig.relayRecoveryWorthy) return;
    final now = DateTime.now();
    if (now.difference(_lastRelayReprobe) < _relayReprobeInterval) return;
    _lastRelayReprobe = now;
    unawaited(
      FirebaseConfig.probeRelayReachability().then((ok) {
        if (!ok) return;
        debugPrint(
          'Relay del S7 recuperado en caliente: las lecturas vuelven a '
          'pasar por el telefono y dejan de pagar cuota.',
        );
      }),
    );
  }

  void stopSync() {
    _syncPollingTimer?.cancel();
    _syncPollingTimer = null;
    _lanSessionTimer?.cancel();
    _lanSessionTimer = null;
    _lanDiscoveryTimer?.cancel();
    _lanDiscoveryTimer = null;
    _udpAnnounceTimer?.cancel();
    _udpAnnounceTimer = null;
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _cloudDevicesTimer?.cancel();
    _cloudDevicesTimer = null;
    _cloudCommandsTimer?.cancel();
    _cloudCommandsTimer = null;
    // Aviso de apagado: la lista en nube del resto de equipos deja de mostrar
    // este dispositivo en vez de esperar a que caduque el heartbeat.
    unawaited(_publishPresence(online: false));
    _lanHttpServer?.close(force: true);
    _lanHttpServer = null;
    _udpSocket?.close();
    _udpSocket = null;
    _udpBroadcastSocket?.close();
    _udpBroadcastSocket = null;
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // En el móvil la reproducción debe saltar sola a la PC cuando la PC está
      // encendida y comparte la misma cuenta (petición de Cesar: "en automático").
      final defaultAutoPlay = !isDesktopHost;
      _autoPlayOnPc = prefs.getBool(_autoPlayOnPcPrefKey) ?? defaultAutoPlay;

      // Hosts anunciados por UDP o visitados en sesiones anteriores: se sondean
      // primero para que la vinculación sea inmediata al abrir la app.
      final remembered =
          prefs.getStringList(_knownHostsPrefKey) ?? const <String>[];
      for (final entry in remembered) {
        final parts = entry.split(':');
        final ip = parts.first;
        if (ip.isEmpty) continue;
        final port = parts.length > 1
            ? int.tryParse(parts[1]) ?? _defaultPort
            : _defaultPort;
        _liveHosts.add('$ip:$port');
        unawaited(_probePeer(ip, port));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('InutilSync: no se pudieron cargar hosts LAN guardados: $e');
    }
  }

  Future<void> setAutoPlayOnPc(bool value) async {
    _autoPlayOnPc = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoPlayOnPcPrefKey, value);
    } catch (e) {
      debugPrint('InutilSync: no se pudo guardar autoPlayOnPc: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 1. SERVIDOR HTTP LOCAL (LAN RECEIVER)
  // ---------------------------------------------------------------------------
  Future<void> _startLanServer() async {
    if (_lanHttpServer != null) return;

    for (var port = _defaultPort; port <= _defaultPort + 5; port++) {
      try {
        _lanHttpServer = await HttpServer.bind(
          InternetAddress.anyIPv4,
          port,
          shared: true,
        );
        _currentLanPort = port;
        debugPrint('Inútil LAN Server activo en puerto: $_currentLanPort');
        break;
      } catch (e) {
        debugPrint('Inútil LAN: puerto $port ocupado, intentando siguiente...');
      }
    }

    if (_lanHttpServer == null) return;

    _lanHttpServer!.listen(
      _handleHttpRequest,
      onError: (e) {
        debugPrint('Inútil LAN Server error: $e');
      },
    );
  }

  void _handleHttpRequest(HttpRequest request) async {
    // Cabeceras CORS abiertas para red local
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add(
      'Access-Control-Allow-Methods',
      'GET, POST, OPTIONS',
    );
    request.response.headers.add(
      'Access-Control-Allow-Headers',
      'Content-Type',
    );

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    try {
      if (path == '/api/ping') {
        final payload = {
          'status': 'ok',
          'deviceId': _auth.deviceId,
          'deviceName': _auth.deviceName,
          'platform': _auth.devicePlatform,
          'userEmail': _auth.currentUser?.email ?? '',
          'uid': _auth.currentUser?.uid ?? '',
          'port': _currentLanPort,
          'isHost': isDesktopHost,
          'appVersion': AppConstants.appVersion,
        };
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(payload));
        await request.response.close();
        return;
      }

      if (path == '/api/session') {
        // Respondemos con **lo que este equipo muestra**, no con su snapshot
        // local congelado: si somos el mando, la sesión del altavoz. Y con la
        // posición estimada a este instante, para que el otro mando no vea la
        // barra quieta entre escrituras del altavoz.
        final session = remoteSession;
        final Map<String, dynamic> payload;
        if (session == null) {
          payload = {
            'activeDeviceId': _auth.deviceId,
            'activeDeviceName': _auth.deviceName,
            'activeDevicePlatform': _auth.devicePlatform,
            'isPlaying': false,
            'trackId': '',
          };
        } else {
          final now = DateTime.now();
          payload = session.toJson();
          payload['positionMs'] = session.estimatedPositionMsAt(now);
          // Siempre acompañar la posición estimada con el instante exacto en
          // que fue calculada; si se deja el `updatedAt` viejo, el receptor
          // vuelve a sumar `(now - updatedAt)` y la barra corre a 2x-10x.
          payload['updatedAt'] = now.toUtc().toIso8601String();
        }
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(payload));
        await request.response.close();
        return;
      }

      if (path == '/api/release') {
        // La PC hace de servidor de versiones: quien tenga el artefacto
        // descargado puede actualizar al resto de la casa sin pasar por la nube.
        final manifest = _readLocalReleaseManifest();
        request.response
          ..statusCode = manifest == null ? HttpStatus.notFound : HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(manifest ?? {'status': 'no releases'}));
        await request.response.close();
        return;
      }

      if (path.startsWith('/api/releases/') && request.method == 'GET') {
        await _serveLocalReleaseFile(request, path);
        return;
      }

      if (path == '/api/command' && request.method == 'POST') {
        final bodyStr = await utf8.decodeStream(request);
        final json = jsonDecode(bodyStr) as Map<String, dynamic>;
        final commandType =
            json['commandType'] as String? ?? json['command'] as String? ?? '';
        final param = json['param'];

        // Control de acceso: sólo mandan dispositivos de la MISMA cuenta.
        // Si este host no tiene sesión iniciada no hay nada que comparar.
        final myUid = _auth.currentUser?.uid ?? '';
        final myEmail = _auth.currentUser?.email ?? '';
        final issuerUid = json['issuerUid'] as String? ?? '';
        final issuerEmail = json['issuerEmail'] as String? ?? '';
        final sameAccount =
            myUid.isEmpty && myEmail.isEmpty ||
            (issuerUid.isNotEmpty && issuerUid == myUid) ||
            (issuerEmail.isNotEmpty &&
                myEmail.isNotEmpty &&
                issuerEmail.trim().toLowerCase() ==
                    myEmail.trim().toLowerCase());
        if (!sameAccount) {
          debugPrint(
            'Inútil LAN: comando $commandType descartado (otra cuenta).',
          );
          request.response
            ..statusCode = HttpStatus.forbidden
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'status': 'unauthorized'}));
          await request.response.close();
          return;
        }

        debugPrint('Inútil LAN: comando recibido: $commandType');

        if (onRemoteCommandReceived != null && commandType.isNotEmpty) {
          // La reproducción que vamos a iniciar aquí viene de otro dispositivo:
          // no debe reenviarse de vuelta (evita el ping-pong móvil <-> PC).
          _routeSuppressedUntil = DateTime.now().add(_routeSuppression);
          if (commandType == 'playTrack') {
            _clearHandoffAuthority();
            _currentRemoteSession = null;
          }
          unawaited(
            onRemoteCommandReceived!(commandType, normalizeRemoteParam(param)),
          );
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'status': 'ok',
              'command': commandType,
              // `executed` sólo es verdadero si hay un reproductor escuchando los
              // comandos: así el emisor sabe si el mando hizo algo de verdad.
              'executed':
                  onRemoteCommandReceived != null && commandType.isNotEmpty,
            }),
          );
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (e) {
      debugPrint('Inútil LAN request error ($path): $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  /// Manifiesto de versión que este equipo tiene en `~/inutil-releases/release.json`.
  /// Sirve para actualizar el móvil u otro PC desde la red local cuando la nube
  /// todavía no tiene publicado el lanzamiento.
  Map<String, dynamic>? _readLocalReleaseManifest() {
    final file = InutilReleasePaths.manifestFile();
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) return null;
      // Reescribimos las URLs relativas para que apunten a este servidor.
      final manifest = Map<String, dynamic>.from(decoded);
      for (final key in const [
        'apkDownloadUrl',
        'linuxDownloadUrl',
        'linuxDebDownloadUrl',
        'linuxRpmDownloadUrl',
        'windowsDownloadUrl',
        'macosDownloadUrl',
        'macosArm64DownloadUrl',
        'macosX64DownloadUrl',
      ]) {
        final value = (manifest[key] ?? '').toString().trim();
        if (value.startsWith('/')) {
          manifest[key] = 'http://$localAddressHint:$_currentLanPort$value';
        }
      }
      return manifest;
    } catch (_) {
      return null;
    }
  }

  Future<void> _serveLocalReleaseFile(HttpRequest request, String path) async {
    final name = Uri.decodeComponent(path.substring('/api/releases/'.length));
    final file = InutilReleasePaths.artifact(name);
    if (file == null || !file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    // Aceptamos Range para que la descarga del móvil se pueda reanudar.
    final total = file.lengthSync();
    final range = request.headers.value(HttpHeaders.rangeHeader);
    var start = 0;
    var end = total - 1;
    if (range != null && range.startsWith('bytes=')) {
      final spec = range.substring(6).split('-');
      start = int.tryParse(spec.first.trim()) ?? 0;
      if (spec.length > 1 && spec[1].trim().isNotEmpty) {
        end = int.tryParse(spec[1].trim()) ?? total - 1;
      }
      if (start >= total || end >= total || start > end) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$total',
      );
    }

    request.response.headers.contentType = ContentType.parse(
      'application/octet-stream',
    );
    request.response.contentLength = end - start + 1;
    await request.response.addStream(file.openRead(start, end + 1));
    await request.response.close();
  }

  /// Primera IP local no loopback: se usa para reescribir rutas relativas del
  /// manifiesto y para mostrarla en el panel de dispositivos.
  String get localAddressHint => _localAddressCache ?? '127.0.0.1';

  String? _localAddressCache;

  /// Manifiesto de versión publicado por alguno de los pares de la misma cuenta
  /// (`GET /api/release`). Permite actualizar un dispositivo desde otro de la
  /// misma red cuando la nube aún no tiene el lanzamiento.
  Future<Map<String, dynamic>?> fetchReleaseManifestFromPeers() async {
    for (final peer in discoveredPeers) {
      if (!isSameAccountAsPeer(peer)) continue;
      final client = HttpClient()
        ..connectionTimeout = const Duration(milliseconds: 1200);
      try {
        final request = await client.getUrl(
          Uri.parse('${peer.httpBaseUrl}/api/release'),
        );
        final response = await request.close().timeout(
          const Duration(milliseconds: 1500),
        );
        if (response.statusCode != 200) continue;
        final decoded = jsonDecode(await utf8.decodeStream(response));
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        // El par no expone versiones (versión antigua de la app).
      } finally {
        client.close();
      }
    }
    return null;
  }

  /// true si el par pertenece a la misma cuenta que este dispositivo.
  bool isSameAccountAsPeer(LanDevicePeer peer) {
    if (peer.deviceId == _autoPairedPeer?.deviceId) return true;
    return peer.isSameAccount(_auth.currentUser?.email, _auth.currentUser?.uid);
  }

  /// Convierte [peer] en el destino preferido de los comandos remotos y carga
  /// la sesión que está sonando allí (el usuario elige el dispositivo desde el
  /// panel "Conectar a un dispositivo").
  void selectPeer(LanDevicePeer peer) {
    if (_autoPairedPeer?.deviceId == peer.deviceId) return;
    _autoPairedPeer = peer;
    _currentRemoteSession = null;
    // Desde ya somos el mando: no nos declararemos altavoz aunque tardemos en
    // ver la sesión de [peer] (LAN lenta, documento caducado, etc.).
    _markHandoffToPeer(deviceId: peer.deviceId, deviceName: peer.deviceName);
    debugPrint(
      'Inútil LAN: destino remoto seleccionado: ${peer.deviceName} (${peer.ip}:${peer.port})',
    );
    unawaited(_fetchSessionFromPeer(peer));
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 1b. ANUNCIOS UDP (DESCUBRIMIENTO ACTIVO EN CUALQUIER RED LOCAL)
  // ---------------------------------------------------------------------------
  // El barrido HTTP no escala a cualquier red, así que cada dispositivo anuncia
  // su presencia por UDP cada 2 s. Quien oye un anuncio sondea el HTTP del
  // anunciante para confirmar la cuenta y la sesión en curso.
  void _startUdpAnnouncer() {
    if (_udpSocket != null) return;
    unawaited(_bindUdp());
    _udpAnnounceTimer?.cancel();
    _udpAnnounceTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_announceUdp()),
    );
  }

  Future<void> _bindUdp() async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _udpPort,
        reuseAddress: true,
        reusePort: true,
      );
      socket.broadcastEnabled = true;
      socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          final datagram = socket.receive();
          if (datagram == null) return;
          _handleUdpAnnouncement(datagram.address.address, datagram.data);
        },
        onError: (e) {
          debugPrint('Inútil LAN UDP error: $e');
        },
      );
      _udpSocket = socket;
      debugPrint('Inútil LAN: anuncios UDP activos en $_udpPort');
    } catch (e) {
      debugPrint('Inútil LAN: no se pudo abrir el UDP $_udpPort ($e)');
    }
  }

  Future<void> _announceUdp() async {
    final socket = _udpSocket;
    if (socket == null) return;

    final user = _auth.currentUser;
    final payload = utf8.encode(
      jsonEncode({
        'app': 'inutil_music',
        'deviceId': _auth.deviceId,
        'deviceName': _auth.deviceName,
        'platform': _auth.devicePlatform,
        'port': _currentLanPort,
        'uid': user?.uid ?? '',
        'email': user?.email ?? '',
        'isHost': isDesktopHost,
      }),
    );

    final targets = <InternetAddress>[
      InternetAddress('255.255.255.255', type: InternetAddressType.IPv4),
    ];
    // Broadcast dirigido por subred (192.168.x.255): algunos routers descartan
    // el broadcast limitado 255.255.255.255.
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          _localAddressCache ??= ip;
          final dot = ip.lastIndexOf('.');
          if (dot <= 0) continue;
          final broadcast = '${ip.substring(0, dot)}.255';
          if (broadcast == ip) continue;
          targets.add(
            InternetAddress(broadcast, type: InternetAddressType.IPv4),
          );
        }
      }
    } catch (e) {
      debugPrint(
        'InutilSync: no se pudieron listar interfaces para broadcast UDP: $e',
      );
    }

    for (final target in targets) {
      try {
        socket.send(payload, target, _udpPort);
      } catch (_) {}
    }
  }

  void _handleUdpAnnouncement(String senderIp, List<int> data) {
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['app'] != 'inutil_music') return;

      final deviceId = decoded['deviceId'] as String? ?? '';
      if (deviceId.isEmpty || deviceId == _auth.deviceId) return;

      final port = decoded['port'] is int
          ? decoded['port'] as int
          : int.tryParse(decoded['port']?.toString() ?? '') ?? _defaultPort;

      // Confirmamos por HTTP (cuenta, nombre real y sesión actual).
      unawaited(_probePeer(senderIp, port));
    } catch (e) {
      debugPrint('InutilSync: paquete UDP de descubrimiento inválido: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 2. DESCUBRIMIENTO AUTOMÁTICO EN LA RED LOCAL (AUTO-PAIRING MISMA CUENTA)
  // ---------------------------------------------------------------------------
  void _startLanDiscovery() {
    _lanDiscoveryTimer?.cancel();
    _lanDiscoveryTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_performLanDiscovery());
    });
    // Primer intento inmediato
    unawaited(_performLanDiscovery());
  }

  Future<void> _performLanDiscovery() async {
    // 1. Emulador de Android -> host de la máquina física (10.0.2.2).
    if (Platform.isAndroid) {
      unawaited(_probePeer('10.0.2.2', _defaultPort));
    }

    // 2. Barrido completo de la subred /24 una vez por minuto (los hosts que ya
    //    respondieron se refrescan cada 3 s sin coste adicional).
    if (DateTime.now().difference(_lastSubnetSweep) >
        const Duration(seconds: 60)) {
      _lastSubnetSweep = DateTime.now();
      unawaited(_sweepLocalSubnets());
    }

    // 3. Refrescar la sesión de los peers que siguen en línea.
    for (final peer in _discoveredPeers.values.toList()) {
      if (!isPeerOnline(peer)) continue;
      unawaited(_fetchSessionFromPeer(peer));
    }

    // 4. Retirar peers que desaparecieron (Wi-Fi apagado, PC apagada...).
    _pruneStalePeers();
  }

  Future<void> _sweepLocalSubnets() async {
    final subnets = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (!ip.startsWith('192.168.') &&
              !ip.startsWith('10.') &&
              !ip.startsWith('172.')) {
            continue;
          }
          final dot = ip.lastIndexOf('.');
          if (dot > 0) subnets.add(ip.substring(0, dot));
        }
      }
    } catch (e) {
      debugPrint('InutilSync: no se pudieron listar subredes LAN: $e');
    }
    // Red del emulador de Android.
    subnets.add('10.0.2');

    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 250);
    try {
      for (final subnet in subnets) {
        final futures = <Future<void>>[];
        for (var i = 1; i <= 254; i++) {
          final ip = '$subnet.$i';
          if (_liveHosts.contains('$ip:$_defaultPort')) continue;
          futures.add(_probePeer(ip, _defaultPort, client: client));
        }
        await Future.wait(futures);
      }
    } catch (e) {
      debugPrint('Inútil LAN: barrido de subred incompleto ($e)');
    } finally {
      client.close();
    }
  }

  void _pruneStalePeers() {
    final stale = _discoveredPeers.entries
        .where((entry) => !isPeerOnline(entry.value))
        .map((entry) => entry.key)
        .toList();

    for (final id in stale) {
      _discoveredPeers.remove(id);
    }

    final paired = _autoPairedPeer;
    var dropped = false;
    if (paired != null && stale.contains(paired.deviceId)) {
      debugPrint('Inútil LAN: ${paired.deviceName} dejó de responder.');
      _autoPairedPeer = null;
      dropped = true;
      // El mismo equipo puede seguir vivo en la nube (está en otra red o su
      // firewall tapa el puerto): el mando no se queda huérfano, pasa a
      // comandarlo por Firestore.
      _maybeAutoPairFromCloud();
      if (_autoPairedPeer != null) {
        notifyListeners();
        return;
      }
    } else if (paired != null &&
        paired.isCloudOnly &&
        !_cloudDevices.containsKey(paired.deviceId)) {
      debugPrint(
        'Inútil Connect: ${paired.deviceName} dejó de escribir su '
        'presencia en la nube.',
      );
      _autoPairedPeer = null;
      dropped = true;
    }

    // Sin un destino al que mandar los comandos, la sesión que mostrábamos del
    // equipo remoto ya no es accionable: el reproductor local vuelve a mandar
    // — pero solo después de la gracia de cesión, para que un mando silencioso
    // no pise con su snapshot congelado la sesión del altavoz que acaba de
    // perder de vista.
    if (dropped &&
        _currentRemoteSession != null &&
        _currentRemoteSession!.activeDeviceId != _auth.deviceId) {
      _markHandoffToPeer(
        deviceId: _currentRemoteSession!.activeDeviceId,
        deviceName: _currentRemoteSession!.activeDeviceName,
      );
      _currentRemoteSession = null;
    }
    // Sin cambios reales no hay que reconstruir el panel de dispositivos cada
    // tres segundos.
    if (!dropped && stale.isEmpty) return;
    notifyListeners();
  }

  Future<void> _probePeer(String ip, int port, {HttpClient? client}) async {
    // Si es este mismo servidor en este mismo puerto, no sondearnos a nosotros mismos
    final isSelfPort = port == _currentLanPort;
    if (isSelfPort && (ip == '127.0.0.1' || ip == 'localhost')) return;

    final ownClient = client == null;
    final httpClient =
        client ??
        (HttpClient()..connectionTimeout = const Duration(milliseconds: 1200));
    try {
      final request = await httpClient.getUrl(
        Uri.parse('http://$ip:$port/api/ping'),
      );
      final response = await request.close().timeout(
        const Duration(milliseconds: 1500),
      );
      if (response.statusCode == 200) {
        final bodyStr = await utf8.decodeStream(response);
        final map = jsonDecode(bodyStr) as Map<String, dynamic>;
        final deviceId = map['deviceId'] as String? ?? '';

        // Ignorar si es este mismo dispositivo
        if (deviceId == _auth.deviceId || deviceId.isEmpty) return;

        final peer = LanDevicePeer(
          ip: ip,
          port: port,
          deviceId: deviceId,
          deviceName: map['deviceName'] as String? ?? 'Dispositivo Inútil',
          platform: map['platform'] as String? ?? 'generic',
          userEmail: map['userEmail'] as String? ?? '',
          uid: map['uid'] as String? ?? '',
          isHost: map['isHost'] as bool? ?? false,
          appVersion: map['appVersion'] as String? ?? '',
        );

        _discoveredPeers[deviceId] = peer;
        _liveHosts.add('$ip:$port');
        unawaited(_persistLiveHosts());

        // VINCULACIÓN AUTOMÁTICA SI ES LA MISMA CUENTA
        // Estabilidad: si ya estamos vinculados a un peer LAN vivo (especialmente
        // una PC/Laptop host o el altavoz activo), NO dejamos que un segundo
        // celular inactivo en la misma red secuestre `_autoPairedPeer`.
        final myEmail = _auth.currentUser?.email;
        final myUid = _auth.currentUser?.uid;
        final isSame = peer.isSameAccount(myEmail, myUid);
        final currentPaired = _autoPairedPeer;
        final currentStillOnline =
            currentPaired != null &&
            !currentPaired.isCloudOnly &&
            isPeerOnline(currentPaired);
        final isActiveSpeakerPeer =
            _currentRemoteSession != null &&
            _currentRemoteSession!.activeDeviceId == peer.deviceId;
        final upgradesToHost =
            currentPaired != null && !currentPaired.isHost && peer.isHost;
        final shouldAdoptAutoPair =
            isSame &&
            (currentPaired == null ||
                currentPaired.isCloudOnly ||
                !currentStillOnline ||
                isActiveSpeakerPeer ||
                upgradesToHost);

        if (shouldAdoptAutoPair &&
            (currentPaired == null ||
                currentPaired.deviceId != peer.deviceId ||
                currentPaired.isCloudOnly)) {
          _autoPairedPeer = peer;
          debugPrint(
            'Inútil LAN: ¡Auto-vinculado con éxito con ${peer.deviceName} (${peer.ip}) por misma cuenta!',
          );
          notifyListeners();
          // Arrastrar la sesión que ya está sonando en el peer para que el
          // mando remoto muestre desde el primer momento "Sonando en ...".
          unawaited(_fetchSessionFromPeer(peer));
        } else if (currentPaired?.deviceId == peer.deviceId) {
          _autoPairedPeer = peer;
        }

        notifyListeners();
      }
    } catch (_) {
      // Endpoint no disponible o fuera de línea
    } finally {
      if (ownClient) httpClient.close();
    }
  }

  /// Guarda la lista de hosts que respondieron para que la próxima sesión de la
  /// app se vincule al instante, sin esperar al barrido de la subred.
  Future<void> _persistLiveHosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hosts = _liveHosts.take(12).toList();
      await prefs.setStringList(_knownHostsPrefKey, hosts);
    } catch (e) {
      debugPrint('InutilSync: no se pudieron persistir hosts LAN: $e');
    }
  }

  Future<void> _fetchSessionFromPeer(LanDevicePeer peer) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 1200);
    try {
      final request = await client.getUrl(
        Uri.parse('${peer.httpBaseUrl}/api/session'),
      );
      final response = await request.close().timeout(
        const Duration(milliseconds: 1500),
      );
      if (response.statusCode == 200) {
        final bodyStr = await utf8.decodeStream(response);
        final map = jsonDecode(bodyStr) as Map<String, dynamic>;
        final session = PlaybackSyncSession.fromJson(map);

        if (session.trackId.isNotEmpty) {
          // Nunca adoptar nuestro propio estado rebotado por un mando remoto:
          // el altavoz local es la única fuente de verdad de su reproducción y
          // aceptar el eco produce un bucle de ping-pong de posición/updatedAt.
          if (session.activeDeviceId == _auth.deviceId) {
            return;
          }
          if (session.isPlaying) {
            _confirmRemoteHandover(session.trackId);
          }
          // Igual que con la nube: mientras esperamos que el altavoz estrene la
          // canción que le enviamos, su respuesta todavía puede describir la
          // anterior y pisaría la sesión optimista del mando.
          if (!_isAwaitingRemoteHandover(session)) {
            if (session.activeDeviceId != _auth.deviceId &&
                !_awaitingRemoteSpeaker &&
                !declaredSpeakerIsLive(
                  session: session,
                  myDeviceId: _auth.deviceId,
                  liveDeviceIds: _liveSpeakerIds(),
                )) {
              // El par nos reenvía un altavoz que ya no existe (un mando que
              // responde con la sesión heredada): no lo adoptamos, y lo que
              // mostramos pasa a ser nuestra propia sesión, no la de un
              // fantasma.
              _currentRemoteSession = null;
            } else {
              final guarded = DateTime.now().isBefore(
                _optimisticControlGuardUntil,
              );
              final prev = _currentRemoteSession;
              if (guarded &&
                  prev != null &&
                  prev.trackId == session.trackId &&
                  prev.activeDeviceId == session.activeDeviceId) {
                _currentRemoteSession = session.copyWith(
                  positionMs: prev.estimatedPositionMs,
                  isPlaying: prev.isPlaying,
                  volume: prev.volume,
                  shuffleEnabled: prev.shuffleEnabled,
                  repeatMode: prev.repeatMode,
                  updatedAt: DateTime.now(),
                );
              } else {
                _currentRemoteSession = session;
              }
              if (session.activeDeviceId != _auth.deviceId) {
                _markHandoffToPeer(
                  deviceId: session.activeDeviceId,
                  deviceName: session.activeDeviceName,
                );
              }
            }
            notifyListeners();
          }
        } else if (_currentRemoteSession != null &&
            _currentRemoteSession!.activeDeviceId == peer.deviceId &&
            (_currentLocalSession == null ||
                _handedOffDeviceId == peer.deviceId)) {
          // El peer ya no tiene nada cargado: el mando deja de mostrar sesión.
          // Antes esta rama estaba atada a que el mando no tuviera canción
          // local, y como su snapshot local queda congelado al ceder, nunca
          // llegaba a ejecutarse: el reproductor se quedaba "reproduciendo".
          _currentRemoteSession = null;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint(
        'InutilSync: error consultando sesión de ${peer.httpBaseUrl}: $e',
      );
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // 2b. RELAY EN LA NUBE: PRESENCIA + COLA DE COMANDOS (FIRESTORE)
  // ---------------------------------------------------------------------------
  // Es lo que hace que «Conectar a un dispositivo» funcione como Spotify
  // Connect: sin abrir puertos, sin depender de la misma subred y aunque el
  // móvil vaya por datos. Cada equipo escribe su presencia en
  // `users/{uid}/devices/{deviceId}`; quien manda un comando escribe en
  // `users/{uid}/commands/{id}` y el destino lo ejecuta al leerlo. La red local
  // sigue siendo la vía rápida cuando ambos equipos comparten Wi-Fi.

  void _startCloudRelay() {
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(presenceInterval, (_) {
      unawaited(_publishPresence());
    });
    _cloudDevicesTimer?.cancel();
    _cloudDevicesTimer = Timer.periodic(devicesPollInterval, (_) {
      unawaited(_pollCloudDevices());
    });
    unawaited(_publishPresence());
    unawaited(_pollCloudDevices());
    _scheduleCommandPoll();
  }

  /// Sondeo de la cola de comandos con cadencia adaptativa: lento mientras no
  /// hay nada en juego y rápido durante unos segundos después de mandar uno,
  /// para que el play/pause remoto conteste sin esperar al ciclo de 3 s.
  void _scheduleCommandPoll() {
    _cloudCommandsTimer?.cancel();
    final burst = DateTime.now().isBefore(_commandsBurstUntil);
    final targets = connectTargets;
    final hasCloudOnlyPeer = targets.any((peer) => peer.isCloudOnly);
    final hasAnyLanPeer = _discoveredPeers.values.any(isPeerOnline);
    final interval = cloudCommandPollInterval(
      burst: burst,
      hasCloudOnlyPeer: hasCloudOnlyPeer,
      hasAnyLanPeer: hasAnyLanPeer,
      hasAnyOnlinePeer: targets.isNotEmpty,
    );
    _cloudCommandsTimer = Timer(interval, () {
      unawaited(_pollCloudCommands().whenComplete(_scheduleCommandPoll));
    });
  }

  /// Escribe el heartbeat `users/{uid}/devices/{deviceId}` de este equipo.
  ///
  /// Con [online] en `false` se anuncia el apagado para que el resto de la casa
  /// deje de mostrarlo en la lista al instante. [force] salta el recorte de
  /// frecuencia y se usa cuando cambia algo que el usuario sí ve (pasa de
  /// «en pausa» a «sonando», por ejemplo).
  Future<void> _publishPresence({
    bool online = true,
    bool force = false,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    if (!online && _cloudBlocked) return;

    final now = DateTime.now();
    final sinceLastPush = now.millisecondsSinceEpoch - _lastPresencePushMs;
    if (online &&
        !force &&
        sinceLastPush <
            (presenceInterval - const Duration(seconds: 3)).inMilliseconds) {
      return;
    }
    if (online) _lastPresencePushMs = now.millisecondsSinceEpoch;

    final local = _currentLocalSession;
    final remote = _currentRemoteSession;
    final isMe = isCurrentDeviceActive;
    final shown = isMe ? local : remote;

    try {
      final written = await _firestore.setDocument(
        'users/$uid/$devicesCollection/${_auth.deviceId}',
        <String, dynamic>{
          'deviceId': _auth.deviceId,
          'name': _auth.deviceName,
          'platform': _auth.devicePlatform,
          'isHost': isDesktopHost,
          'isOnline': online,
          'lastSeenMs': now.millisecondsSinceEpoch,
          'appVersion': AppConstants.appVersion,
          'lanIp': _localAddressCache ?? '',
          'lanPort': _currentLanPort,
          'activeDeviceId': isMe
              ? _auth.deviceId
              : (remote?.activeDeviceId ?? ''),
          'activeDeviceName': isMe
              ? _auth.deviceName
              : (remote?.activeDeviceName ?? ''),
          'isPlaying': shown?.isPlaying ?? false,
          'trackId': shown?.trackId ?? '',
          'title': shown?.title ?? '',
          'artist': shown?.artist ?? '',
          'updatedAt': now,
        },
      );
      if (written) {
        _cloudPollFailures = 0;
        _cloudPollBlockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
      } else {
        _noteCloudUnavailable();
      }
    } on FirestoreOperationException catch (error) {
      final capped = _noteCloudUnavailable();
      if (_cloudPollFailures == 1) {
        debugPrint(
          'Inútil Connect: no se pudo publicar la presencia ($error). '
          'Reintentando en $capped s.',
        );
      }
    } catch (_) {
      _noteCloudUnavailable();
    }
  }

  /// Lee `users/{uid}/devices` y mantiene la lista de equipos en línea de la
  /// cuenta, vengan o no de esta red local.
  Future<void> _pollCloudDevices() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    if (_cloudBlocked) return;

    try {
      final docs = await _firestore.listCollection(
        'users/$uid/$devicesCollection',
      );
      _cloudPollFailures = 0;
      _cloudPollBlockedUntil = DateTime.fromMillisecondsSinceEpoch(0);

      final now = DateTime.now();
      final fresh = <String, LanDevicePeer>{};
      for (final doc in docs) {
        final peer = peerFromCloudDoc(
          doc,
          myDeviceId: _auth.deviceId,
          now: now,
        );
        if (peer == null) continue;
        fresh[peer.deviceId] = peer;

        // Aunque Android/routers descarten los broadcasts UDP, cada equipo
        // anuncia su IP LAN privada dentro de `users/{uid}/devices/{id}`.
        // Probamos esa IP en segundo plano: si están en el mismo Wi-Fi, el
        // enlace sube a LAN directa (<50 ms y 0 lecturas/escrituras Firebase).
        final existingLan = _discoveredPeers[peer.deviceId];
        if (existingLan == null || !isPeerOnline(existingLan)) {
          final hint = extractProbeableLanEndpoint(doc);
          if (hint != null) {
            unawaited(_probePeer(hint.ip, hint.port));
          }
        }
      }
      final hadNoPeersBefore = connectTargets.isEmpty;
      _cloudDevices
        ..clear()
        ..addAll(fresh);

      if (hadNoPeersBefore && fresh.isNotEmpty) {
        // Acaba de aparecer un segundo equipo en la cuenta: despertamos los
        // sondeos de sesión/comandos sin esperar el ciclo relajado de 30 s.
        _lastCloudSessionPoll = DateTime.fromMillisecondsSinceEpoch(0);
        _scheduleCommandPoll();
      }
      _maybeAutoPairFromCloud();
      notifyListeners();
    } on FirestoreOperationException catch (error) {
      final capped = _noteCloudUnavailable();
      if (_cloudPollFailures == 1) {
        debugPrint(
          'Inútil Connect: no se pudo leer la lista de dispositivos '
          '($error). Reintentando en $capped s.',
        );
      }
    } catch (_) {
      _noteCloudUnavailable();
    }
  }

  /// Vincula el mando con el PC aunque no compartan red.
  void _maybeAutoPairFromCloud() {
    final current = _autoPairedPeer;
    if (current != null && (isPeerOnline(current) || current.isOnlineNow)) {
      return;
    }
    final candidate = pickAutoPairCandidate(connectTargets);
    if (candidate == null) return;
    _autoPairedPeer = candidate;
    debugPrint(
      'Inútil Connect: vinculado con ${candidate.deviceName} '
      '${candidate.isCloudOnly ? '(vía nube)' : '(red local)'}.',
    );
    notifyListeners();
  }

  /// Sondea la cola `users/{uid}/commands` y ejecuta lo que vaya para este
  /// equipo. Tras cada comando enviado el sondeo se acelera unos segundos para
  /// que el play/pause remoto se note inmediato.
  Future<void> _pollCloudCommands() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    if (_cloudBlocked) return;

    final now = DateTime.now();
    try {
      final docs = await _firestore.listCollection(
        'users/$uid/$commandsCollection',
        pageSize: 40,
      );
      _cloudPollFailures = 0;
      _cloudPollBlockedUntil = DateTime.fromMillisecondsSinceEpoch(0);

      final mine = <CloudCommand>[];
      for (final doc in docs) {
        final command = cloudCommandFromDoc(
          doc,
          myDeviceId: _auth.deviceId,
          now: now,
        );
        if (command == null) continue;
        if (_processedCommandIds.contains(command.id)) continue;
        mine.add(command);
      }
      // Orden cronológico: si llegaron varias canciones, se tocan en orden.
      mine.sort((a, b) {
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return at.compareTo(bt);
      });

      for (final command in mine) {
        _rememberProcessedCommand(command.id);
        await _runCloudCommand(command);
      }

      await _cleanupCloudCommands(docs, now: now);
    } on FirestoreOperationException catch (error) {
      final capped = _noteCloudUnavailable();
      if (_cloudPollFailures == 1) {
        debugPrint(
          'Inútil Connect: no se pudo leer la cola de comandos '
          '($error). Reintentando en $capped s.',
        );
      }
    } catch (_) {
      _noteCloudUnavailable();
    }
  }

  /// Marca el comando como entregado y lo pasa al reproductor local.
  Future<void> _runCloudCommand(CloudCommand command) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        await _firestore.setDocument(
          'users/$uid/$commandsCollection/${command.id}',
          {'deliveredAtMs': DateTime.now().millisecondsSinceEpoch},
        );
      }
    } catch (e) {
      // Si no se puede marcar, igual se ejecuta: a estas alturas mandó otro
      // equipo y el usuario espera que suene.
      debugPrint(
        'InutilSync: no se pudo marcar comando ${command.id} como entregado: $e',
      );
    }

    if (command.type.isEmpty || onRemoteCommandReceived == null) return;

    // La reproducción que arranca aquí viene de otro dispositivo: no debe
    // reenviarse de vuelta (evita el ping-pong móvil <-> PC).
    _routeSuppressedUntil = DateTime.now().add(_routeSuppression);
    unawaited(
      onRemoteCommandReceived!(
        command.type,
        normalizeRemoteParam(command.param),
      ),
    );
  }

  /// Borra los comandos ya entregados y los caducados: la cola no crece y la
  /// lectura periódica se mantiene en una o dos documentos.
  Future<void> _cleanupCloudCommands(
    List<Map<String, dynamic>> docs, {
    required DateTime now,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    for (final doc in docs) {
      final id = (doc['commandId'] ?? doc['docId'] ?? '').toString();
      if (id.isEmpty) continue;
      final delivered = _millisToDateTime(doc['deliveredAtMs']);
      final createdAt = _millisToDateTime(doc['createdAtMs']);
      final staleByAge =
          createdAt != null && now.difference(createdAt) > commandTtl;
      if (delivered == null && !staleByAge) continue;
      try {
        await _firestore.deleteDocument('users/$uid/$commandsCollection/$id');
      } catch (e) {
        debugPrint('InutilSync: no se pudo purgar comando $id: $e');
      }
    }
  }

  /// Escribe un comando en la cola de la nube para [targetDeviceId].
  Future<bool> sendCloudCommand({
    required String targetDeviceId,
    required String commandType,
    dynamic param,
  }) async =>
      await writeCloudCommand(
        targetDeviceId: targetDeviceId,
        commandType: commandType,
        param: param,
      ) !=
      null;

  /// Igual que [sendCloudCommand] pero devuelve el id del comando escrito (o
  /// `null` si no se pudo escribir), para que el puente con versiones antiguas
  /// use el mismo id y nadie ejecute dos veces la misma orden.
  Future<String?> writeCloudCommand({
    required String targetDeviceId,
    required String commandType,
    dynamic param,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty || targetDeviceId.isEmpty) return null;

    final now = DateTime.now();
    final command = CloudCommand(
      id: commandDocumentId(
        createdAtMs: now.millisecondsSinceEpoch,
        targetDeviceId: targetDeviceId,
        issuerDeviceId: _auth.deviceId,
      ),
      type: commandType,
      targetDeviceId: targetDeviceId,
      issuerDeviceId: _auth.deviceId,
      issuerName: _auth.deviceName,
      param: param,
      createdAt: now,
    );

    try {
      final written = await _firestore.setDocument(
        'users/$uid/$commandsCollection/${command.id}',
        command.toFirestoreDoc(),
      );
      if (!written) {
        _noteCloudUnavailable();
        return null;
      }
      // Aceleramos el sondeo propio unos segundos para reflejar el resultado.
      _commandsBurstUntil = now.add(commandsBurstWindow);
      _scheduleCommandPoll();
      return command.id;
    } on FirestoreOperationException catch (error) {
      _noteCloudUnavailable();
      debugPrint(
        'Inútil Connect: comando $commandType no llegó a la nube '
        '($error).',
      );
      return null;
    } catch (_) {
      _noteCloudUnavailable();
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // 3. ENVÍO DE COMANDOS EN TIEMPO REAL A LA PC / CELULAR (P2P LAN)
  // ---------------------------------------------------------------------------

  void _applyOptimisticCommand(String commandType, dynamic param) {
    final current = _currentRemoteSession;
    if (current == null) return;
    final now = DateTime.now();
    switch (commandType) {
      case 'pause':
        _optimisticControlGuardUntil = now.add(
          const Duration(milliseconds: 1400),
        );
        _currentRemoteSession = current.copyWith(
          isPlaying: false,
          positionMs: current.estimatedPositionMsAt(now),
          updatedAt: now,
        );
        notifyListeners();
        break;
      case 'play':
      case 'resume':
        _optimisticControlGuardUntil = now.add(
          const Duration(milliseconds: 1400),
        );
        final restartFromZero =
            current.durationMs > 0 &&
            current.positionMs >= current.durationMs - 2000;
        _currentRemoteSession = current.copyWith(
          isPlaying: true,
          positionMs: restartFromZero ? 0 : current.positionMs,
          updatedAt: now,
        );
        notifyListeners();
        break;
      case 'seek':
        final ms = int.tryParse(param?.toString() ?? '');
        if (ms != null) {
          _optimisticControlGuardUntil = now.add(
            const Duration(milliseconds: 1800),
          );
          _currentRemoteSession = current.copyWith(
            positionMs: ms.clamp(
              0,
              current.durationMs > 0 ? current.durationMs : ms,
            ),
            updatedAt: now,
          );
          notifyListeners();
        }
        break;
      case 'setVolume':
        final vol = double.tryParse(param?.toString() ?? '');
        if (vol != null) {
          _optimisticControlGuardUntil = now.add(
            const Duration(milliseconds: 1400),
          );
          _currentRemoteSession = current.copyWith(
            volume: vol.clamp(0.0, 1.0),
            updatedAt: now,
          );
          notifyListeners();
        }
        break;
      case 'setShuffle':
        final enabled = param == true || param?.toString() == 'true';
        _optimisticControlGuardUntil = now.add(
          const Duration(milliseconds: 1400),
        );
        _currentRemoteSession = current.copyWith(
          shuffleEnabled: enabled,
          updatedAt: now,
        );
        notifyListeners();
        break;
      case 'setRepeat':
        final mode = (param?.toString() ?? 'off').trim();
        _optimisticControlGuardUntil = now.add(
          const Duration(milliseconds: 1400),
        );
        _currentRemoteSession = current.copyWith(
          repeatMode: mode.isEmpty ? 'off' : mode,
          updatedAt: now,
        );
        notifyListeners();
        break;
    }
  }

  /// Envía un comando remoto por LAN (Play, Pause, Skip, Prev, Seek, Volume,
  /// Shuffle, Repeat).
  Future<bool> sendLanCommand({
    required String commandType,
    dynamic param,
    LanDevicePeer? targetPeer,
  }) async {
    final peer = targetPeer ?? _autoPairedPeer;
    if (peer == null) return false;
    // Un peer visto sólo en la nube no tiene IP útil: su comando viaja por
    // Firestore, y el llamador (sendRemoteControlCommand) se encarga de ello.
    if (peer.isCloudOnly) return false;

    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 1500);
    try {
      final request = await client.postUrl(
        Uri.parse('${peer.httpBaseUrl}/api/command'),
      );
      request.headers.contentType = ContentType.json;
      final payload = jsonEncode({
        'commandType': commandType,
        'param': param,
        'issuerDeviceId': _auth.deviceId,
        'issuerUid': _auth.currentUser?.uid ?? '',
        'issuerEmail': _auth.currentUser?.email ?? '',
      });
      request.write(payload);
      final response = await request.close().timeout(
        const Duration(milliseconds: 2000),
      );
      final success = response.statusCode == HttpStatus.ok;
      if (success) {
        _applyOptimisticCommand(commandType, param);
        // Tras un skip o seek, refrescar sesión LAN pronto para reflejar pista
        // y duración reales en <500 ms.
        if (commandType == 'next' || commandType == 'previous') {
          Future<void>.delayed(const Duration(milliseconds: 600), () {
            unawaited(_fetchSessionFromPeer(peer));
          });
        }
      }
      return success;
    } catch (e) {
      debugPrint('Error enviando comando LAN: $e');
      return false;
    } finally {
      client.close();
    }
  }

  /// Transfiere y reproduce una canción (y su cola) directamente en el par remoto.
  Future<bool> playTrackOnPeer({
    required String trackId,
    required String title,
    required String artist,
    String? album,
    String? thumbnailUrl,
    int positionMs = 0,
    int durationMs = 0,
    List<Map<String, dynamic>>? queue,
    int queueIndex = 0,
    double? volume,
    bool? shuffleEnabled,
    String? repeatMode,
    LanDevicePeer? targetPeer,
  }) async {
    final activeId = _currentRemoteSession?.activeDeviceId ?? '';
    final peer =
        targetPeer ??
        (activeId.isNotEmpty && activeId != _auth.deviceId
            ? _discoveredPeers[activeId] ?? _cloudDevices[activeId]
            : null) ??
        (_autoPairedPeer != null
            ? _discoveredPeers[_autoPairedPeer!.deviceId] ?? _autoPairedPeer
            : null) ??
        pickAutoPairCandidate(connectTargets);
    if (peer == null) return false;
    _autoPairedPeer = peer;

    // GUARD: Evitar reenvíos duplicados de `playTrack` al mismo altavoz
    // dentro de una ráfaga de snapshots del mismo toque (incluso con cola).
    final dedupKey = '${peer.deviceId}|$trackId';
    final now = DateTime.now();
    if (targetPeer == null &&
        _lastPlayTrackDedupKey == dedupKey &&
        now.difference(_lastPlayTrackDedupAt) <
            const Duration(milliseconds: 1500)) {
      return true;
    }
    if (targetPeer == null &&
        (queue == null || queue.isEmpty) &&
        _currentRemoteSession != null &&
        _currentRemoteSession!.activeDeviceId == peer.deviceId &&
        _currentRemoteSession!.trackId == trackId &&
        _currentRemoteSession!.isPlaying) {
      return true;
    }
    _lastPlayTrackDedupKey = dedupKey;
    _lastPlayTrackDedupAt = now;

    final lanQueue = (queue ?? const <Map<String, dynamic>>[])
        .take(30)
        .toList(growable: false);
    final cloudQueue = lanQueue.take(15).toList(growable: false);

    final lanTrackParam = <String, dynamic>{
      'trackId': trackId,
      'title': title,
      'artist': artist,
      'album': album ?? '',
      'thumbnailUrl': thumbnailUrl ?? '',
      'positionMs': positionMs,
      if (durationMs > 0) 'durationMs': durationMs,
      if (lanQueue.isNotEmpty) 'queue': lanQueue,
      if (lanQueue.isNotEmpty) 'queueIndex': queueIndex,
      'shuffleEnabled': ?shuffleEnabled,
      'repeatMode': ?repeatMode,
    };

    var success = false;
    if (!peer.isCloudOnly) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(milliseconds: 2000);
      try {
        final request = await client.postUrl(
          Uri.parse('${peer.httpBaseUrl}/api/command'),
        );
        request.headers.contentType = ContentType.json;
        final payload = jsonEncode({
          'commandType': 'playTrack',
          'param': lanTrackParam,
          'issuerDeviceId': _auth.deviceId,
          'issuerUid': _auth.currentUser?.uid ?? '',
          'issuerEmail': _auth.currentUser?.email ?? '',
        });
        request.write(payload);
        final response = await request.close().timeout(
          const Duration(milliseconds: 2500),
        );
        success = response.statusCode == HttpStatus.ok;
      } catch (e) {
        debugPrint('Error ejecutando playTrack en peer LAN: $e');
        success = false;
      } finally {
        client.close();
      }
    }

    // Si era sólo nube o la LAN falló (ej. firewall / cambio de Wi-Fi),
    // enviamos por el relay de la nube para que nunca se pierda la selección.
    if (!success) {
      final cloudTrackParam = <String, dynamic>{
        ...lanTrackParam,
        if (cloudQueue.isNotEmpty) 'queue': cloudQueue,
      };
      success = await sendCloudCommand(
        targetDeviceId: peer.deviceId,
        commandType: 'playTrack',
        param: cloudTrackParam,
      );
    }

    if (success) {
      final prev = _currentRemoteSession;
      _currentRemoteSession = PlaybackSyncSession(
        activeDeviceId: peer.deviceId,
        activeDeviceName: peer.deviceName,
        activeDevicePlatform: peer.platform,
        trackId: trackId,
        title: title,
        artist: artist,
        album: album ?? '',
        thumbnailUrl: thumbnailUrl ?? '',
        positionMs: positionMs,
        durationMs: durationMs,
        isPlaying: true,
        volume: volume ?? prev?.volume ?? 1.0,
        shuffleEnabled: shuffleEnabled ?? prev?.shuffleEnabled ?? false,
        repeatMode: repeatMode ?? prev?.repeatMode ?? 'off',
        queue: lanQueue,
        queueIndex: queueIndex,
        // Marca de tiempo propia: sin ella el sondeo de la nube, que aún
        // describe la canción anterior, borraría esta sesión en menos de 3 s
        // y el mando volvería a mostrar la canción que ya venía sonando.
        updatedAt: DateTime.now(),
      );
      _markHandoffToPeer(deviceId: peer.deviceId, deviceName: peer.deviceName);
      _beginRemoteHandover(trackId);
      _optimisticControlGuardUntil = DateTime.now().add(
        const Duration(milliseconds: 3500),
      );
      notifyListeners();
      // Sólo forzamos presencia en nube si no hay enlace LAN directo.
      if (peer.isCloudOnly) {
        unawaited(_publishPresence(force: true));
      }
    }

    return success;
  }

  // ---------------------------------------------------------------------------
  /// Backoff compartido del sondeo y de las escrituras de sesión.
  ///
  /// Cuando Firestore responde 403/5xx (proyecto mal configurado, reglas o
  /// credenciales) repetir la misma petición cada tres segundos sólo gasta
  /// batería y llena el log. Se duplica la espera hasta 60 s y se reutiliza
  /// para no escribir mientras la nube siga marcada como no disponible.
  /// Devuelve los segundos de espera aplicados.
  int _noteCloudUnavailable() {
    _cloudPollFailures = (_cloudPollFailures + 1).clamp(0, 8);
    final seconds = 3 * (1 << _cloudPollFailures);
    final capped = seconds > 60 ? 60 : seconds;
    _cloudPollBlockedUntil = DateTime.now().add(Duration(seconds: capped));
    return capped;
  }

  /// true mientras se sabe que la nube no responde: no hay que insistir.
  bool get _cloudBlocked => DateTime.now().isBefore(_cloudPollBlockedUntil);

  // 4. MÉTODOS DE COMPATIBILIDAD CON FIRESTORE Y LOCAL
  // ---------------------------------------------------------------------------
  Future<void> _pollPlaybackSession() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // Backoff: sin credenciales válidas de proyecto Firestore cada sondeo
    // devuelve 403 y la app gastaría batería pidiendo cada 3 segundos.
    final now = DateTime.now();
    if (now.isBefore(_cloudPollBlockedUntil)) return;

    try {
      final doc = await _firestore.getDocument(
        'users/$uid/playback_session/current',
      );
      _cloudPollFailures = 0;
      _cloudPollBlockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
      if (doc != null) {
        final session = PlaybackSyncSession.fromJson(doc);
        // Si el documento en la nube habla de nosotros mismos y ya tenemos
        // sesión local viva, no dejamos que un snapshot viejo de Firestore pise
        // el estado real del altavoz.
        if (session.activeDeviceId == _auth.deviceId &&
            _currentLocalSession != null) {
          _clearHandoffAuthority();
          return;
        }
        final stored = _currentRemoteSession;
        final fresher = shouldAdoptDocument(stored: stored, doc: session);
        // La LAN es más rápida; el documento en la nube sólo gana si es al
        // menos igual de reciente, para no pisar el estado que acabamos de
        // leer del par. Tampoco gana mientras esperamos que confirme una
        // canción que le acabamos de transferir: aún hablaría de la anterior.
        if (fresher && !_isAwaitingRemoteHandover(session)) {
          final refresh =
              stored == null ||
              session.trackId != stored.trackId ||
              session.isPlaying != stored.isPlaying ||
              (session.updatedAt != null &&
                  stored.updatedAt != null &&
                  session.updatedAt!.isAfter(stored.updatedAt!));
          _currentRemoteSession = session;
          // Antes solo se adoptaba cuando cambió de canción: por eso la barra
          // del mando se quedaba quieta, la posición del altavoz nunca llegaba
          // hasta que empezaba otra pista.
          if (refresh) notifyListeners();
        }

        // Mientras la nube siga nombrando a otro equipo como el que suena,
        // conservamos la autoridad de mando: un mando silencioso no debe
        // creerse altavoz solo porque su sondeo llegue lento o vacío.
        if (session.activeDeviceId == _auth.deviceId) {
          _clearHandoffAuthority();
        } else if (declaredSpeakerIsLive(
          session: session,
          myDeviceId: _auth.deviceId,
          liveDeviceIds: _liveSpeakerIds(),
        )) {
          _markHandoffToPeer(
            deviceId: session.activeDeviceId,
            deviceName: session.activeDeviceName,
          );
        } else if (!_awaitingRemoteSpeaker) {
          // La nube nombra como altavoz a un equipo que ya no escribe
          // presencia: es un id fantasma y no hay nadie al otro lado. Soltamos
          // la sesión remota para que `visibleSession` devuelva la nuestra y
          // el audio local vuelva a andar; al ser otra vez el altavoz, la
          // próxima escritura de sesión reemplaza el id fantasma y el ciclo se
          // cierra solo, sin reiniciar la app.
          _currentRemoteSession = null;
          notifyListeners();
        }

        if (session.activeDeviceId == _auth.deviceId) {
          if (session.pendingCommandId.isNotEmpty &&
              session.pendingCommandId != _lastProcessedCommandId &&
              !_processedCommandIds.contains(session.pendingCommandId) &&
              session.pendingCommandIssuerId != _auth.deviceId) {
            _lastProcessedCommandId = session.pendingCommandId;
            _rememberProcessedCommand(session.pendingCommandId);
            if (onRemoteCommandReceived != null) {
              await onRemoteCommandReceived!(
                session.pendingCommandType,
                normalizeRemoteParam(session.pendingCommandParam),
              );
            }
          }
        }
      }
    } on FirestoreOperationException catch (error) {
      // 403/500: el proyecto o sus reglas no dejan leer. Subir el intervalo
      // de sondeo de 3 s a 60 s como máximo en lugar de castigar la red y la
      // batería con la misma petición cada tres segundos.
      final capped = _noteCloudUnavailable();
      if (_cloudPollFailures == 1) {
        debugPrint(
          'Inútil Sync: nube no disponible ($error). '
          'Reintentando en $capped s.',
        );
      }
    } catch (_) {
      _noteCloudUnavailable();
    }
  }

  Future<void> notifyPlaybackProgress({
    required String trackId,
    required String title,
    required String artist,
    required String? album,
    required String? thumbnailUrl,
    required int positionMs,
    required int durationMs,
    required bool isPlaying,
    double volume = 1.0,
    bool shuffleEnabled = false,
    String repeatMode = 'off',
    List<Map<String, dynamic>> queue = const <Map<String, dynamic>>[],
    int queueIndex = 0,
    bool force = false,
  }) async {
    final now = DateTime.now();
    final session = PlaybackSyncSession(
      activeDeviceId: _auth.deviceId,
      activeDeviceName: _auth.deviceName,
      activeDevicePlatform: _auth.devicePlatform,
      trackId: trackId,
      title: title,
      artist: artist,
      album: album ?? '',
      thumbnailUrl: thumbnailUrl ?? '',
      positionMs: positionMs,
      durationMs: durationMs,
      isPlaying: isPlaying,
      volume: volume.clamp(0.0, 1.0),
      shuffleEnabled: shuffleEnabled,
      repeatMode: repeatMode,
      queue: queue,
      queueIndex: queueIndex,
      updatedAt: now,
    );

    _currentLocalSession = session;

    // Sólo si este dispositivo es el altavoz activo actualizamos remoteSession.
    // Así una PC actuando como mando remoto de un celular no pisa la sesión.
    if (isCurrentDeviceActive) {
      _currentRemoteSession = session;
    }

    notifyListeners();

    // Debouncing inteligente para ahorrar cuota de Firestore:
    // - En LAN `/api/session` ya sirve cada actualización al instante (0 cuota).
    // - A Firestore sólo escribimos en cambios reales (`force`) cada >= 1.5 s,
    //   o cada 25 s durante reproducción continua (antes cada 8 s).
    final timeSinceLastPush = now.difference(_lastPositionPushTime);
    if ((!force && timeSinceLastPush.inSeconds < 25) ||
        (force && timeSinceLastPush.inMilliseconds < 1500)) {
      return;
    }
    _lastPositionPushTime = now;

    final uid = _auth.currentUser?.uid;
    // Sólo el dispositivo que está sonando de verdad escribe la sesión en la
    // nube; si no, el móvil apagado pisaría la sesión de la PC. Y mientras se
    // sepa que la nube no responde no se insiste: la LAN ya mantiene la
    // sincronía entre dispositivos de la misma casa.
    if (uid != null && isCurrentDeviceActive && !_cloudBlocked) {
      try {
        final written = await _firestore.setDocument(
          'users/$uid/playback_session/current',
          session.toCloudJson(),
        );
        if (!written) {
          _noteCloudUnavailable();
        }
      } catch (_) {
        _noteCloudUnavailable();
      }
    }

    // La tarjeta de este equipo en la lista de dispositivos muestra lo que
    // está sonando: se refresca cuando cambia algo visible (play, pause,
    // canción nueva), no en cada tick de posición.
    if (force && uid != null && uid.isNotEmpty) {
      unawaited(_publishPresence(force: true));
    }
  }

  Future<void> transferPlaybackToThisDevice({
    required String trackId,
    required String title,
    required String artist,
    required String? album,
    required String? thumbnailUrl,
    required int positionMs,
    required int durationMs,
    required bool isPlaying,
    double volume = 1.0,
    bool shuffleEnabled = false,
    String repeatMode = 'off',
    List<Map<String, dynamic>> queue = const <Map<String, dynamic>>[],
    int queueIndex = 0,
  }) async {
    // El usuario pidió explícitamente reproducir AQUÍ: bloqueamos el reenvío
    // automático al par remoto y apagamos autoPlayOnPc para que las siguientes
    // canciones sigan sonando en este equipo.
    _routeSuppressedUntil = DateTime.now().add(_routeSuppression);
    unawaited(setAutoPlayOnPc(false));

    // Si hay un altavoz remoto activo, pausarlo (preferiendo LAN directa).
    final activeId = _currentRemoteSession?.activeDeviceId ?? '';
    final peer =
        (activeId.isNotEmpty && activeId != _auth.deviceId
            ? _discoveredPeers[activeId] ?? _cloudDevices[activeId]
            : null) ??
        (_autoPairedPeer != null
            ? _discoveredPeers[_autoPairedPeer!.deviceId] ?? _autoPairedPeer
            : null);
    if (peer != null) {
      unawaited(
        peer.isCloudOnly
            ? sendCloudCommand(
                targetDeviceId: peer.deviceId,
                commandType: 'pause',
              )
            : sendLanCommand(commandType: 'pause', targetPeer: peer),
      );
    }
    // El usuario pidió explícitamente el audio para este equipo: ya no
    // esperamos a ningún altavoz remoto, somos nosotros.
    _clearHandoffAuthority();
    _currentRemoteSession = null;

    await notifyPlaybackProgress(
      trackId: trackId,
      title: title,
      artist: artist,
      album: album,
      thumbnailUrl: thumbnailUrl,
      positionMs: positionMs,
      durationMs: durationMs,
      isPlaying: isPlaying,
      volume: volume,
      shuffleEnabled: shuffleEnabled,
      repeatMode: repeatMode,
      queue: queue,
      queueIndex: queueIndex,
      force: true,
    );
  }

  Future<void> sendRemoteControlCommand({
    required String commandType,
    dynamic param,
  }) async {
    final activeId = _currentRemoteSession?.activeDeviceId ?? '';
    final peer =
        (activeId.isNotEmpty && activeId != _auth.deviceId
            ? _discoveredPeers[activeId] ?? _cloudDevices[activeId]
            : null) ??
        (_autoPairedPeer != null
            ? _discoveredPeers[_autoPairedPeer!.deviceId] ?? _autoPairedPeer
            : null) ??
        pickAutoPairCandidate(connectTargets);
    if (peer != null) {
      _autoPairedPeer = peer;
    }

    // 1. Vía rápida por LAN: responde en milisegundos cuando el puerto 52445
    //    del destino está alcanzable (0 lecturas/escrituras de Firebase).
    if (peer != null && !peer.isCloudOnly) {
      final ok = await sendLanCommand(
        commandType: commandType,
        param: param,
        targetPeer: peer,
      );
      if (ok) {
        if (commandType == 'play' ||
            commandType == 'resume' ||
            commandType == 'pause') {
          _markPeerAsActiveDevice(peer, playing: commandType != 'pause');
        }
        return;
      }
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    // 2. Relay en la nube con el destino explícito (`users/{uid}/commands`).
    final targetId =
        peer?.deviceId ?? _currentRemoteSession?.activeDeviceId ?? '';
    final now = DateTime.now();
    final known = peer ?? _cloudDevices[targetId] ?? _discoveredPeers[targetId];
    String? cloudCommandId;
    if (targetId.isNotEmpty) {
      cloudCommandId = await writeCloudCommand(
        targetDeviceId: targetId,
        commandType: commandType,
        param: param,
      );
      if (cloudCommandId != null) {
        _applyOptimisticCommand(commandType, param);
        if (known != null &&
            (commandType == 'play' ||
                commandType == 'resume' ||
                commandType == 'pause')) {
          _markPeerAsActiveDevice(known, playing: commandType != 'pause');
        }
      }
    }

    // 3. Puente con versiones anteriores (2.5.7 y previas), que sólo miran los
    //    campos `pendingCommand*` del documento de sesión compartido. Se salta
    //    cuando el destino ya anuncia una versión con cola de comandos, y
    //    comparte el id de la cola para que, si los dos canales llegan, el
    //    comando se ejecute una sola vez y no dos.
    if (_currentRemoteSession != null &&
        needsLegacyCommandBridge(known?.appVersion)) {
      final legacyId =
          cloudCommandId ?? '${now.millisecondsSinceEpoch}_${_auth.deviceId}';
      _rememberProcessedCommand(legacyId);
      final updated = {
        ..._currentRemoteSession!.toJson(),
        'pendingCommandId': legacyId,
        'pendingCommandType': commandType,
        // Un mapa pasado por `toString()` ya no vuelve a leerse como mapa, así
        // que el parámetro se guarda como JSON.
        'pendingCommandParam': param == null
            ? ''
            : (param is String ? param : jsonEncode(param)),
        'pendingCommandIssuerId': _auth.deviceId,
        'updatedAt': now.toUtc().toIso8601String(),
      };
      try {
        await _firestore.setDocument(
          'users/$uid/playback_session/current',
          updated,
        );
      } catch (e) {
        debugPrint(
          'InutilSync: no se pudo actualizar playback_session/current: $e',
        );
      }
    }
  }

  /// Marca al par remoto como el dispositivo que está sonando, de forma que la
  /// interfaz del mando muestre «Sonando en la PC» y el reproductor local no
  /// sobrescriba la sesión compartida.
  void _markPeerAsActiveDevice(LanDevicePeer peer, {required bool playing}) {
    final base = _currentRemoteSession ?? _currentLocalSession;
    if (base == null) return;
    if (base.activeDeviceId == peer.deviceId && base.isPlaying == playing) {
      return;
    }

    _currentRemoteSession = PlaybackSyncSession(
      activeDeviceId: peer.deviceId,
      activeDeviceName: peer.deviceName,
      activeDevicePlatform: peer.platform,
      trackId: base.trackId,
      title: base.title,
      artist: base.artist,
      album: base.album,
      thumbnailUrl: base.thumbnailUrl,
      positionMs: base.positionMs,
      durationMs: base.durationMs,
      isPlaying: playing,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }
}

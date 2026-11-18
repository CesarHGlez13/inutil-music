import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/release_paths.dart';
import 'firebase_auth_service.dart';
import 'firebase_firestore_service.dart';

/// Dispositivo descubierto en la red local (Wi-Fi).
class LanDevicePeer {
  LanDevicePeer({
    required this.ip,
    required this.port,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    this.userEmail = '',
    this.uid = '',
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  final String ip;
  final int port;
  final String deviceId;
  final String deviceName;
  final String platform;
  final String userEmail;
  final String uid;
  DateTime lastSeen;

  String get httpBaseUrl => 'http://$ip:$port';

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
      lastSeen: DateTime.tryParse(json['lastSeen']?.toString() ?? '') ?? DateTime.now(),
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
  final DateTime? updatedAt;
  final String pendingCommandId;
  final String pendingCommandType;
  final dynamic pendingCommandParam;
  final String pendingCommandIssuerId;

  Map<String, dynamic> toJson() => {
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
    'updatedAt': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    'pendingCommandId': pendingCommandId,
    'pendingCommandType': pendingCommandType,
    'pendingCommandParam': pendingCommandParam?.toString() ?? '',
    'pendingCommandIssuerId': pendingCommandIssuerId,
  };

  factory PlaybackSyncSession.fromJson(Map<String, dynamic> map) {
    return PlaybackSyncSession(
      activeDeviceId: map['activeDeviceId'] as String? ?? '',
      activeDeviceName: map['activeDeviceName'] as String? ?? 'Dispositivo Inútil',
      activeDevicePlatform: map['activeDevicePlatform'] as String? ?? 'generic',
      trackId: map['trackId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      artist: map['artist'] as String? ?? '',
      album: map['album'] as String? ?? '',
      thumbnailUrl: map['thumbnailUrl'] as String? ?? '',
      positionMs: map['positionMs'] as int? ?? 0,
      durationMs: map['durationMs'] as int? ?? 0,
      isPlaying: map['isPlaying'] as bool? ?? false,
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

/// Callback para ejecutar acciones en el reproductor local cuando llega un comando remoto.
typedef RemotePlaybackCommandHandler = Future<void> Function(
  String commandType,
  dynamic param,
);

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

  /// Un peer deja de considerarse "en línea" tras este tiempo sin verse.
  static const Duration _peerTtl = Duration(seconds: 12);

  /// Ventana en la que no reenviamos la reproducción a otro dispositivo
  /// después de ejecutar un comando remoto (evita el bucle PC <-> móvil).
  static const Duration _routeSuppression = Duration(seconds: 6);

  final InutilAuthService _auth = InutilAuthService.instance;
  final InutilFirestoreService _firestore = InutilFirestoreService.instance;

  HttpServer? _lanHttpServer;
  RawDatagramSocket? _udpBroadcastSocket;
  RawDatagramSocket? _udpSocket;
  int _currentLanPort = _defaultPort;

  PlaybackSyncSession? _currentLocalSession;
  PlaybackSyncSession? _currentRemoteSession;
  Timer? _syncPollingTimer;
  Timer? _lanDiscoveryTimer;
  int _cloudPollFailures = 0;
  DateTime _cloudPollBlockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPositionPushTime = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastProcessedCommandId = '';
  RemotePlaybackCommandHandler? onRemoteCommandReceived;

  final Map<String, LanDevicePeer> _discoveredPeers = {};
  LanDevicePeer? _autoPairedPeer;
  bool _autoPlayOnPc = false;

  /// Hosts (anunciados por UDP o recordados de sesiones anteriores) que ya
  /// respondieron a /api/ping: no hace falta volver a barrerlos cada 3 s.
  final Set<String> _liveHosts = {};
  Timer? _udpAnnounceTimer;
  DateTime _lastSubnetSweep = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _routeSuppressedUntil = DateTime.fromMillisecondsSinceEpoch(0);

  PlaybackSyncSession? get remoteSession => _currentRemoteSession ?? _currentLocalSession;
  LanDevicePeer? get autoPairedPeer => _autoPairedPeer;
  List<LanDevicePeer> get discoveredPeers =>
      _discoveredPeers.values.where(isPeerOnline).toList();
  bool get autoPlayOnPc => _autoPlayOnPc;
  int get currentLanPort => _currentLanPort;

  /// true si este dispositivo debe comportarse como "sumidero" de audio
  /// (escritorio) en lugar de como control remoto (móvil/tablet).
  static bool get isDesktopHost => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  /// true si acabamos de ejecutar un comando remoto: nuestra reproducción
  /// local es "heredada" y no debe reenviarse a otro dispositivo.
  bool get isPlaybackRouteSuppressed =>
      DateTime.now().isBefore(_routeSuppressedUntil);

  static bool isPeerOnline(LanDevicePeer peer) =>
      DateTime.now().difference(peer.lastSeen) < _peerTtl;

  /// Si este dispositivo es el que actualmente reproduce el audio físicamente.
  bool get isCurrentDeviceActive {
    if (_currentRemoteSession == null) return true;
    return _currentRemoteSession!.activeDeviceId == _auth.deviceId;
  }

  String get activeDeviceDisplayName {
    if (_currentRemoteSession == null) return _auth.deviceName;
    return _currentRemoteSession!.activeDeviceName;
  }

  /// Inicia el servidor LAN y la sincronización automática.
  void startSync() {
    _loadPreferences();
    _startLanServer();
    _startUdpAnnouncer();
    _startLanDiscovery();

    _syncPollingTimer?.cancel();
    _syncPollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollPlaybackSession();
    });
    _pollPlaybackSession();
  }

  void stopSync() {
    _syncPollingTimer?.cancel();
    _syncPollingTimer = null;
    _lanDiscoveryTimer?.cancel();
    _lanDiscoveryTimer = null;
    _udpAnnounceTimer?.cancel();
    _udpAnnounceTimer = null;
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
      final remembered = prefs.getStringList(_knownHostsPrefKey) ?? const <String>[];
      for (final entry in remembered) {
        final parts = entry.split(':');
        final ip = parts.first;
        if (ip.isEmpty) continue;
        final port =
            parts.length > 1 ? int.tryParse(parts[1]) ?? _defaultPort : _defaultPort;
        _liveHosts.add('$ip:$port');
        unawaited(_probePeer(ip, port));
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setAutoPlayOnPc(bool value) async {
    _autoPlayOnPc = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoPlayOnPcPrefKey, value);
    } catch (_) {}
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

    _lanHttpServer!.listen(_handleHttpRequest, onError: (e) {
      debugPrint('Inútil LAN Server error: $e');
    });
  }

  void _handleHttpRequest(HttpRequest request) async {
    // Cabeceras CORS abiertas para red local
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

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
          'isHost': Platform.isLinux || Platform.isWindows,
        };
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(payload));
        await request.response.close();
        return;
      }

      if (path == '/api/session') {
        final session = _currentLocalSession ?? _currentRemoteSession;
        final payload = session?.toJson() ?? {
          'activeDeviceId': _auth.deviceId,
          'activeDeviceName': _auth.deviceName,
          'activeDevicePlatform': _auth.devicePlatform,
          'isPlaying': false,
          'trackId': '',
        };
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
        final commandType = json['commandType'] as String? ?? json['command'] as String? ?? '';
        final param = json['param'];

        // Control de acceso: sólo mandan dispositivos de la MISMA cuenta.
        // Si este host no tiene sesión iniciada no hay nada que comparar.
        final myUid = _auth.currentUser?.uid ?? '';
        final myEmail = _auth.currentUser?.email ?? '';
        final issuerUid = json['issuerUid'] as String? ?? '';
        final issuerEmail = json['issuerEmail'] as String? ?? '';
        final sameAccount = myUid.isEmpty && myEmail.isEmpty ||
            (issuerUid.isNotEmpty && issuerUid == myUid) ||
            (issuerEmail.isNotEmpty &&
                myEmail.isNotEmpty &&
                issuerEmail.trim().toLowerCase() == myEmail.trim().toLowerCase());
        if (!sameAccount) {
          debugPrint('Inútil LAN: comando $commandType descartado (otra cuenta).');
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
          unawaited(onRemoteCommandReceived!(commandType, param));
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'status': 'ok',
            'command': commandType,
            // `executed` sólo es verdadero si hay un reproductor escuchando los
            // comandos: así el emisor sabe si el mando hizo algo de verdad.
            'executed': onRemoteCommandReceived != null && commandType.isNotEmpty,
          }));
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
      for (final key in const ['apkDownloadUrl', 'linuxDownloadUrl']) {
        final value = (manifest[key] ?? '').toString().trim();
        if (value.startsWith('/')) {
          manifest[key] =
              'http://$localAddressHint:$_currentLanPort$value';
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

    request.response.headers.contentType = ContentType.parse('application/octet-stream');
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
    debugPrint('Inútil LAN: destino remoto seleccionado: ${peer.deviceName} (${peer.ip}:${peer.port})');
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
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        _handleUdpAnnouncement(datagram.address.address, datagram.data);
      }, onError: (e) {
        debugPrint('Inútil LAN UDP error: $e');
      });
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
    final payload = utf8.encode(jsonEncode({
      'app': 'inutil_music',
      'deviceId': _auth.deviceId,
      'deviceName': _auth.deviceName,
      'platform': _auth.devicePlatform,
      'port': _currentLanPort,
      'uid': user?.uid ?? '',
      'email': user?.email ?? '',
      'isHost': isDesktopHost,
    }));

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
          targets.add(InternetAddress(broadcast, type: InternetAddressType.IPv4));
        }
      }
    } catch (_) {}

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
    } catch (_) {}
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
    if (DateTime.now().difference(_lastSubnetSweep) > const Duration(seconds: 60)) {
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
    } catch (_) {}
    // Red del emulador de Android.
    subnets.add('10.0.2');

    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 250);
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
    if (stale.isEmpty) return;

    for (final id in stale) {
      _discoveredPeers.remove(id);
    }
    if (_autoPairedPeer != null && stale.contains(_autoPairedPeer!.deviceId)) {
      debugPrint('Inútil LAN: ${_autoPairedPeer!.deviceName} dejó de responder.');
      _autoPairedPeer = null;
      // La reproducción vuelve a este dispositivo si el mando remoto se cayó.
      if (_currentRemoteSession != null &&
          _currentRemoteSession!.activeDeviceId != _auth.deviceId) {
        _currentRemoteSession = null;
      }
    }
    notifyListeners();
  }

  Future<void> _probePeer(String ip, int port, {HttpClient? client}) async {
    // Si es este mismo servidor en este mismo puerto, no sondearnos a nosotros mismos
    final isSelfPort = port == _currentLanPort;
    if (isSelfPort && (ip == '127.0.0.1' || ip == 'localhost')) return;

    final ownClient = client == null;
    final httpClient = client ??
        (HttpClient()..connectionTimeout = const Duration(milliseconds: 1200));
    try {
      final request = await httpClient.getUrl(Uri.parse('http://$ip:$port/api/ping'));
      final response = await request.close().timeout(const Duration(milliseconds: 1500));
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
        );

        _discoveredPeers[deviceId] = peer;
        _liveHosts.add('$ip:$port');
        unawaited(_persistLiveHosts());

        // VINCULACIÓN AUTOMÁTICA SI ES LA MISMA CUENTA
        final myEmail = _auth.currentUser?.email;
        final myUid = _auth.currentUser?.uid;
        final isSame = peer.isSameAccount(myEmail, myUid);

        if (isSame && _autoPairedPeer?.deviceId != peer.deviceId) {
          _autoPairedPeer = peer;
          debugPrint('Inútil LAN: ¡Auto-vinculado con éxito con ${peer.deviceName} (${peer.ip}) por misma cuenta!');
          notifyListeners();
          // Arrastrar la sesión que ya está sonando en el peer para que el
          // mando remoto muestre desde el primer momento "Sonando en ...".
          unawaited(_fetchSessionFromPeer(peer));
        } else if (_autoPairedPeer?.deviceId == peer.deviceId) {
          _autoPairedPeer!.lastSeen = DateTime.now();
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
    } catch (_) {}
  }

  Future<void> _fetchSessionFromPeer(LanDevicePeer peer) async {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 1200);
    try {
      final request = await client.getUrl(Uri.parse('${peer.httpBaseUrl}/api/session'));
      final response = await request.close().timeout(const Duration(milliseconds: 1500));
      if (response.statusCode == 200) {
        final bodyStr = await utf8.decodeStream(response);
        final map = jsonDecode(bodyStr) as Map<String, dynamic>;
        final session = PlaybackSyncSession.fromJson(map);

        if (session.trackId.isNotEmpty) {
          _currentRemoteSession = session;
          notifyListeners();
        } else if (_currentRemoteSession != null &&
            _currentRemoteSession!.activeDeviceId == peer.deviceId &&
            _currentLocalSession?.trackId == null) {
          // El peer ya no tiene nada cargado: el mando deja de mostrar sesión.
          _currentRemoteSession = null;
          notifyListeners();
        }
      }
    } catch (_) {} finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // 3. ENVÍO DE COMANDOS EN TIEMPO REAL A LA PC / CELULAR (P2P LAN)
  // ---------------------------------------------------------------------------

  /// Envía un comando remoto por LAN (Play, Pause, Skip, Prev, Seek).
  Future<bool> sendLanCommand({
    required String commandType,
    dynamic param,
    LanDevicePeer? targetPeer,
  }) async {
    final peer = targetPeer ?? _autoPairedPeer;
    if (peer == null) return false;

    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 1500);
    try {
      final request = await client.postUrl(Uri.parse('${peer.httpBaseUrl}/api/command'));
      request.headers.contentType = ContentType.json;
      final payload = jsonEncode({
        'commandType': commandType,
        'param': param,
        'issuerDeviceId': _auth.deviceId,
        'issuerUid': _auth.currentUser?.uid ?? '',
        'issuerEmail': _auth.currentUser?.email ?? '',
      });
      request.write(payload);
      final response = await request.close().timeout(const Duration(milliseconds: 2000));
      final success = response.statusCode == HttpStatus.ok;

      // Actualizar inmediatamente estado local para respuesta táctil instantánea
      if (commandType == 'pause' && _currentRemoteSession != null) {
        _currentRemoteSession = PlaybackSyncSession(
          activeDeviceId: _currentRemoteSession!.activeDeviceId,
          activeDeviceName: _currentRemoteSession!.activeDeviceName,
          activeDevicePlatform: _currentRemoteSession!.activeDevicePlatform,
          trackId: _currentRemoteSession!.trackId,
          title: _currentRemoteSession!.title,
          artist: _currentRemoteSession!.artist,
          album: _currentRemoteSession!.album,
          thumbnailUrl: _currentRemoteSession!.thumbnailUrl,
          positionMs: _currentRemoteSession!.positionMs,
          durationMs: _currentRemoteSession!.durationMs,
          isPlaying: false,
        );
        notifyListeners();
      } else if (commandType == 'play' && _currentRemoteSession != null) {
        _currentRemoteSession = PlaybackSyncSession(
          activeDeviceId: _currentRemoteSession!.activeDeviceId,
          activeDeviceName: _currentRemoteSession!.activeDeviceName,
          activeDevicePlatform: _currentRemoteSession!.activeDevicePlatform,
          trackId: _currentRemoteSession!.trackId,
          title: _currentRemoteSession!.title,
          artist: _currentRemoteSession!.artist,
          album: _currentRemoteSession!.album,
          thumbnailUrl: _currentRemoteSession!.thumbnailUrl,
          positionMs: _currentRemoteSession!.positionMs,
          durationMs: _currentRemoteSession!.durationMs,
          isPlaying: true,
        );
        notifyListeners();
      }

      return success;
    } catch (e) {
      debugPrint('Error enviando comando LAN: $e');
      return false;
    } finally {
      client.close();
    }
  }

  /// Transfiere y reproduce una canción directamente en la PC (o dispositivo par).
  Future<bool> playTrackOnPeer({
    required String trackId,
    required String title,
    required String artist,
    String? album,
    String? thumbnailUrl,
    int positionMs = 0,
    LanDevicePeer? targetPeer,
  }) async {
    final peer = targetPeer ?? _autoPairedPeer;
    if (peer == null) return false;

    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 2000);
    try {
      final request = await client.postUrl(Uri.parse('${peer.httpBaseUrl}/api/command'));
      request.headers.contentType = ContentType.json;
      final payload = jsonEncode({
        'commandType': 'playTrack',
        'param': {
          'trackId': trackId,
          'title': title,
          'artist': artist,
          'album': album ?? '',
          'thumbnailUrl': thumbnailUrl ?? '',
          'positionMs': positionMs,
        },
        'issuerDeviceId': _auth.deviceId,
        'issuerUid': _auth.currentUser?.uid ?? '',
        'issuerEmail': _auth.currentUser?.email ?? '',
      });
      request.write(payload);
      final response = await request.close().timeout(const Duration(milliseconds: 2500));
      final success = response.statusCode == HttpStatus.ok;

      if (success) {
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
          isPlaying: true,
        );
        notifyListeners();
      }

      return success;
    } catch (e) {
      debugPrint('Error ejecutando playTrack en peer LAN: $e');
      return false;
    } finally {
      client.close();
    }
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
      final doc = await _firestore.getDocument('users/$uid/playback_session/current');
      _cloudPollFailures = 0;
      _cloudPollBlockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
      if (doc != null) {
        final session = PlaybackSyncSession.fromJson(doc);
        final fresher = _currentRemoteSession == null ||
            (session.updatedAt != null &&
                (_currentRemoteSession!.updatedAt == null ||
                    session.updatedAt!.isAfter(_currentRemoteSession!.updatedAt!)));
        // La LAN es más rápida; el documento en la nube sólo gana si es más
        // reciente, para no pisar el estado que acabamos de leer del par.
        if (fresher) {
          _currentRemoteSession = session;
          notifyListeners();
        }

        if (session.activeDeviceId == _auth.deviceId) {
          if (session.pendingCommandId.isNotEmpty &&
              session.pendingCommandId != _lastProcessedCommandId &&
              session.pendingCommandIssuerId != _auth.deviceId) {
            _lastProcessedCommandId = session.pendingCommandId;
            if (onRemoteCommandReceived != null) {
              await onRemoteCommandReceived!(
                session.pendingCommandType,
                session.pendingCommandParam,
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
        debugPrint('Inútil Sync: nube no disponible ($error). '
            'Reintentando en $capped s.');
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
      updatedAt: now,
    );

    _currentLocalSession = session;

    // Si este dispositivo es el activo, actualizar remoteSession también
    if (isCurrentDeviceActive) {
      _currentRemoteSession = session;
    }

    notifyListeners();

    // Debouncing para no saturar Firestore
    final timeSinceLastPush = now.difference(_lastPositionPushTime);
    if (!force && timeSinceLastPush.inSeconds < 8) {
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
        final written = await _firestore
            .setDocument('users/$uid/playback_session/current', session.toJson());
        if (!written) {
          _noteCloudUnavailable();
        }
      } catch (_) {
        _noteCloudUnavailable();
      }
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
  }) async {
    // El usuario pidió explícitamente reproducir AQUÍ: bloqueamos el reenvío
    // automático al par remoto durante unos segundos.
    _routeSuppressedUntil = DateTime.now().add(_routeSuppression);

    // Si hay un peer remoto activo, pausarlo
    if (_autoPairedPeer != null) {
      unawaited(sendLanCommand(commandType: 'pause'));
    }
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
      force: true,
    );
  }

  Future<void> sendRemoteControlCommand({
    required String commandType,
    dynamic param,
  }) async {
    // 1. Intentar enviar inmediatamente por LAN
    if (_autoPairedPeer != null) {
      final ok = await sendLanCommand(commandType: commandType, param: param);
      if (ok) {
        _markPeerAsActiveDevice(_autoPairedPeer!, playing: commandType != 'pause');
        return;
      }
    }

    // 2. Si falla LAN, intentar vía Firestore
    final uid = _auth.currentUser?.uid;
    if (uid == null || _currentRemoteSession == null) return;

    final commandId = '${DateTime.now().millisecondsSinceEpoch}_${_auth.deviceId}';
    final updated = {
      ..._currentRemoteSession!.toJson(),
      'pendingCommandId': commandId,
      'pendingCommandType': commandType,
      'pendingCommandParam': param?.toString() ?? '',
      'pendingCommandIssuerId': _auth.deviceId,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      await _firestore.setDocument('users/$uid/playback_session/current', updated);
    } catch (_) {}
  }

  /// Marca al par remoto como el dispositivo que está sonando, de forma que la
  /// interfaz del mando muestre «Sonando en la PC» y el reproductor local no
  /// sobrescriba la sesión compartida.
  void _markPeerAsActiveDevice(LanDevicePeer peer, {required bool playing}) {
    final base = _currentRemoteSession ?? _currentLocalSession;
    if (base == null) return;
    if (base.activeDeviceId == peer.deviceId && base.isPlaying == playing) return;

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

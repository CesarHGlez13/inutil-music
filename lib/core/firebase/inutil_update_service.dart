import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import '../theme/app_ui.dart';
import '../theme/inutil_design_system.dart';
import 'firebase_auth_service.dart';
import 'firebase_config.dart';
import 'firebase_playback_sync_service.dart';

/// Información de lanzamiento y actualización OTA de Inútil Music.
@immutable
class InutilReleaseInfo {
  const InutilReleaseInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    this.apkDownloadUrl = '',
    this.linuxDownloadUrl = '',
    this.mandatory = false,
    required this.publishedAt,
    this.androidDownloads = const <String, String>{},
    this.androidDownloadSizes = const <String, int>{},
    this.androidPackageSizeBytes = 0,
    this.minSupportedVersion = '',
  });

  final String currentVersion;
  final String latestVersion;
  final List<String> releaseNotes;
  final String apkDownloadUrl;
  final String linuxDownloadUrl;
  final bool mandatory;
  final DateTime publishedAt;

  /// Versión mínima que sigue funcionando (kill switch). Cuando la versión
  /// instalada queda por debajo, la app ENTERA deja de ser utilizable: el
  /// diálogo de actualización se vuelve obligatorio y no descartable, aunque
  /// el manifiesto no marque `mandatory`.
  final String minSupportedVersion;

  /// Enlaces por ABI publicados en `androidDownloads`
  /// (`arm64_v8a`, `armeabi_v7a`, `x86_64`, `universal`). Las claves se
  /// guardan normalizadas en minúsculas con guion bajo para que el manifiesto
  /// acepte tanto `arm64-v8a` como `arm64_v8a`.
  final Map<String, String> androidDownloads;

  /// Tamaño en bytes de cada paquete por ABI, usado para mostrar el peso real
  /// en el diálogo antes de descargar.
  final Map<String, int> androidDownloadSizes;

  /// Tamaño en bytes del APK por defecto ([apkDownloadUrl]), o `0` si el
  /// panel de administración no lo publicó.
  final int androidPackageSizeBytes;

  /// Determina si existe una versión superior disponible comparando semver
  /// contra [currentVersion] y [AppConstants.appVersion]. Incluye el kill
  /// switch: si la versión instalada está por debajo de [minSupportedVersion]
  /// también cuenta como actualización pendiente (obligatoria).
  bool get updateAvailable {
    final baseline = currentVersion.trim().isEmpty
        ? AppConstants.appVersion
        : currentVersion.trim();
    return _compareSemver(latestVersion, baseline) > 0 || belowMinSupported;
  }

  /// true cuando la versión instalada ya no soportada (por debajo de
  /// [minSupportedVersion]): la app debe obligar a actualizar para seguir.
  bool get belowMinSupported {
    final min = minSupportedVersion.trim();
    if (min.isEmpty) return false;
    final baseline = currentVersion.trim().isEmpty
        ? AppConstants.appVersion
        : currentVersion.trim();
    return _compareSemver(baseline, min) < 0;
  }

  /// El diálogo se comporta como obligatorio si el manifiesto lo pide O si el
  /// kill switch dejó esta versión obsoleta.
  bool get effectiveMandatory => mandatory || belowMinSupported;

  /// Normaliza un identificador de ABI (`arm64-v8a` → `arm64_v8a`).
  static String normalizeAbiKey(String abi) => abi
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-]+'), '_')
      .replaceAll(RegExp(r'[^a-z0-9_]'), '');

  /// Enlace del APK que corresponde a [abi], cayendo en `universal` y luego en
  /// [apkDownloadUrl] cuando el manifiesto no publica variantes divididas.
  String apkUrlForAbi(String abi) {
    final normalized = normalizeAbiKey(abi);
    for (final key in <String>[
      normalized,
      'universal',
      'split_universal',
    ]) {
      if (key.isEmpty) continue;
      final url = androidDownloads[key]?.trim() ?? '';
      if (url.isNotEmpty) return url;
    }
    return apkDownloadUrl.trim();
  }

  /// Tamaño anunciado del paquete que se descargaría para [abi], o `0`.
  int packageSizeForAbi(String abi) {
    final normalized = normalizeAbiKey(abi);
    for (final key in <String>[normalized, 'universal', 'split_universal']) {
      if (key.isEmpty) continue;
      final size = androidDownloadSizes[key] ?? 0;
      if (size > 0) return size;
    }
    return androidPackageSizeBytes;
  }

  /// Enlace del paquete correspondiente a la plataforma actual.
  ///
  /// En Android prioriza el APK de la ABI del dispositivo cuando el manifiesto
  /// lo publica; por eso [deviceAbi] se pasa explícitamente en lugar de leer
  /// el channel nativo dentro de esta clase, que también se usa en pruebas.
  String downloadUrlForAbi(String deviceAbi) {
    if (Platform.isAndroid || apkDownloadUrl.trim().isNotEmpty) {
      final forAbi = apkUrlForAbi(deviceAbi);
      if (forAbi.isNotEmpty) return forAbi;
    }
    return platformDownloadUrl;
  }

  /// Devuelve el enlace de descarga correspondiente a la plataforma actual.
  String get platformDownloadUrl {
    if (Platform.isAndroid && apkDownloadUrl.trim().isNotEmpty) {
      return apkDownloadUrl.trim();
    }
    if (Platform.isLinux && linuxDownloadUrl.trim().isNotEmpty) {
      return linuxDownloadUrl.trim();
    }
    if (apkDownloadUrl.trim().isNotEmpty) return apkDownloadUrl.trim();
    if (linuxDownloadUrl.trim().isNotEmpty) return linuxDownloadUrl.trim();
    return '';
  }

  Map<String, dynamic> toJson() => {
    'currentVersion': currentVersion,
    'latestVersion': latestVersion,
    'releaseNotes': releaseNotes,
    'apkDownloadUrl': apkDownloadUrl,
    'linuxDownloadUrl': linuxDownloadUrl,
    'mandatory': mandatory,
    'minSupportedVersion': minSupportedVersion,
    'publishedAt': publishedAt.toUtc().toIso8601String(),
    'androidDownloads': androidDownloads,
    'androidDownloadSizes': androidDownloadSizes,
    'androidPackageSizeBytes': androidPackageSizeBytes,
  };

  factory InutilReleaseInfo.fromJson(
    Map<String, dynamic> json, {
    String? currentVersionOverride,
  }) {
    final rawNotes = json['releaseNotes'];
    final notes = <String>[];
    if (rawNotes is List) {
      for (final item in rawNotes) {
        final text = item?.toString().trim() ?? '';
        if (text.isNotEmpty) notes.add(text);
      }
    }

    return InutilReleaseInfo(
      currentVersion:
          currentVersionOverride ??
          (json['currentVersion'] as String?) ??
          AppConstants.appVersion,
      latestVersion: (json['latestVersion'] as String?)?.trim().isNotEmpty == true
          ? (json['latestVersion'] as String).trim()
          : '2.0.0',
      releaseNotes: notes.isEmpty ? _defaultCinemaReleaseNotes : notes,
      apkDownloadUrl: (json['apkDownloadUrl'] as String?)?.trim() ?? '',
      linuxDownloadUrl: (json['linuxDownloadUrl'] as String?)?.trim() ?? '',
      mandatory: json['mandatory'] as bool? ?? false,
      minSupportedVersion:
          (json['minSupportedVersion'] as String?)?.trim() ?? '',
      publishedAt:
          DateTime.tryParse(json['publishedAt']?.toString() ?? '') ??
          DateTime.utc(2026, 11, 16),
      androidDownloads: _parseAndroidDownloads(json['androidDownloads']).urls,
      androidDownloadSizes:
          _parseAndroidDownloads(json['androidDownloadSizes']).sizes,
      androidPackageSizeBytes:
          (json['androidPackageSizeBytes'] as num?)?.toInt() ?? 0,
    );
  }

  /// Paquetes Android publicados en `androidDownloads`.
  ///
  /// Se aceptan las tres formas que puede escribir el panel de administración:
  /// mapa `abi → url`, mapa `abi → {url, sizeBytes}` y lista
  /// `[{abi, url, sizeBytes}]`. Cada clave se normaliza (`arm64-v8a` →
  /// `arm64_v8a`) y los tamaños se leen en bytes.
  static ({Map<String, String> urls, Map<String, int> sizes})
  _parseAndroidDownloads(Object? value) {
    final entries = _downloadEntries(value);
    if (entries.isEmpty) {
      return (
        urls: const <String, String>{},
        sizes: const <String, int>{},
      );
    }
    final urls = <String, String>{};
    final sizes = <String, int>{};
    for (final entry in entries.entries) {
      final key = normalizeAbiKey(entry.key);
      if (key.isEmpty) continue;
      final raw = entry.value;
      final url = raw is Map
          ? _firstString(raw, const ['url', 'downloadUrl', 'apkUrl', 'link'])
          : (raw?.toString().trim() ?? '');
      if (url.isNotEmpty) urls[key] = url;
      final sizeRaw = raw is Map
          ? (raw['sizeBytes'] ?? raw['size'] ?? raw['bytes'])
          : null;
      final size = sizeRaw is num
          ? sizeRaw.toInt()
          : int.tryParse(sizeRaw?.toString().trim() ?? '');
      if (size != null && size > 0) sizes[key] = size;
    }
    return (
      urls: Map<String, String>.unmodifiable(urls),
      sizes: Map<String, int>.unmodifiable(sizes),
    );
  }

  /// Convierte el campo en una lista plana `clave → valor`, aceptando la
  /// codificación REST de Firestore (`mapValue`/`arrayValue`) y JSON plano.
  static Map<String, Object?> _downloadEntries(Object? value) {
    final plain = _plainValue(value);
    if (plain is Map) {
      return plain.map((key, entry) => MapEntry(key.toString(), entry));
    }
    if (plain is List) {
      final result = <String, Object?>{};
      for (final item in plain) {
        if (item is! Map) continue;
        final abi =
            (item['abi'] ?? item['key'] ?? item['name'] ?? '').toString();
        if (abi.trim().isEmpty) continue;
        result[abi] = item;
      }
      return result;
    }
    return const <String, Object?>{};
  }

  static String _firstString(Map<Object?, Object?> map, List<String> keys) {
    for (final key in keys) {
      final raw = map[key]?.toString().trim() ?? '';
      if (raw.isNotEmpty) return raw;
    }
    return '';
  }

  /// Desenvuelve recursivamente los envoltorios de valor de la API REST de
  /// Firestore (`stringValue`, `mapValue`, `arrayValue`, …) para dejar un
  /// objeto Dart plano. Así el mismo parser sirve para la caché local en JSON y
  /// para la respuesta de Firestore.
  static Object? _plainValue(Object? value) {
    if (value is Map) {
      if (value.containsKey('stringValue')) return value['stringValue'];
      if (value.containsKey('integerValue')) return value['integerValue'];
      if (value.containsKey('doubleValue')) return value['doubleValue'];
      if (value.containsKey('booleanValue')) return value['booleanValue'];
      if (value.containsKey('nullValue')) return null;
      if (value.containsKey('timestampValue')) return value['timestampValue'];
      final array = value['arrayValue'];
      if (array is Map) {
        final values = array['values'];
        return values is List
            ? values.map(_plainValue).toList(growable: false)
            : const <Object?>[];
      }
      final fields = value['mapValue'];
      if (fields is Map) {
        final inner = fields['fields'];
        if (inner is Map) {
          return inner.map(
            (key, entry) => MapEntry(key.toString(), _plainValue(entry)),
          );
        }
      }
      return value.map(
        (key, entry) => MapEntry(key.toString(), _plainValue(entry)),
      );
    }
    if (value is List) {
      return value.map(_plainValue).toList(growable: false);
    }
    return value;
  }

  factory InutilReleaseInfo.defaultCinemaEdition({String? currentVersion}) {
    final resolvedVersion = currentVersion ?? AppConstants.appVersion;
    return InutilReleaseInfo(
      currentVersion: resolvedVersion,
      latestVersion: resolvedVersion,
      releaseNotes: _defaultCinemaReleaseNotes,
      apkDownloadUrl: AppConstants.appDownloadUrl,
      linuxDownloadUrl: AppConstants.appDownloadUrl,
      mandatory: false,
      publishedAt: DateTime.utc(2026, 11, 17),
    );
  }

  static const List<String> _defaultCinemaReleaseNotes = [
    'Reproducción fluida incluso en conexiones lentas con caché inteligente.',
    'Video Previews en canciones, perfiles de artistas y álbumes.',
    'Importación de playlists y mejoras de rendimiento y estabilidad.',
  ];

  static int _compareSemver(String a, String b) {
    final partsA = _parseVersionParts(a);
    final partsB = _parseVersionParts(b);
    final length = partsA.length > partsB.length ? partsA.length : partsB.length;
    for (var i = 0; i < length; i++) {
      final valA = i < partsA.length ? partsA[i] : 0;
      final valB = i < partsB.length ? partsB[i] : 0;
      if (valA != valB) return valA.compareTo(valB);
    }
    return 0;
  }

  static List<int> _parseVersionParts(String version) {
    final cleaned = version.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final mainPart = cleaned.split(RegExp(r'[\+\-]')).first;
    return mainPart
        .split('.')
        .map((segment) => int.tryParse(segment.trim()) ?? 0)
        .toList(growable: false);
  }
}

/// Servicio centralizado de actualizaciones OTA e in-app para Inútil Music.
class InutilUpdateService {
  InutilUpdateService._();
  static final InutilUpdateService instance = InutilUpdateService._();

  /// Documento de release en Firestore del proyecto configurado. Se deriva de
  /// `FirebaseConfig.projectId` para que cambiar de proyecto (o usar el
  /// emulador) no exija tocar el código.
  String get _releaseDocumentUrl =>
      'https://firestore.googleapis.com/v1/projects/${FirebaseConfig.projectId}/databases/(default)/documents/app_config/release';
  static const String _prefsCacheKey = 'inutil_music_cached_release_v2';

  /// Repositorio de GitHub donde Cesar publica los APK/binarios como assets de
  /// Release (descargables sin autenticar). Anulable con `--dart-define`.
  static const String releaseRepo = String.fromEnvironment(
    'RELEASE_REPO',
    defaultValue: 'CesarHGlez13/inutil-music',
  );

  /// Manifiesto propio (`release.json`) que Cesar publica junto a los binarios.
  /// Anulable con la variable de entorno `INUTIL_RELEASE_MANIFEST_URL` o desde
  /// Ajustes → Actualizaciones.
  static const String _manifestUrlPrefKey = 'inutil_release_manifest_url';

  /// Manifiesto en el bucket de Cloud Storage del proyecto.
  String get _defaultManifestUrl =>
      '${FirebaseConfig.storageBaseUrl}/releases%2Frelease.json?alt=media';

  /// Manifiesto publicado como asset de la última Release de GitHub
  /// (`releases/latest/download/release.json`); redirige al asset real.
  String get _githubManifestUrl =>
      'https://github.com/$releaseRepo/releases/latest/download/release.json';

  /// Manifiesto forzado por el entorno (`INUTIL_RELEASE_MANIFEST_URL`).
  static String? get _manifestUrlOverride {
    final value =
        (Platform.environment['INUTIL_RELEASE_MANIFEST_URL'] ?? '').trim();
    return value.isEmpty ? null : value;
  }

  /// Manifiesto fijado por las pruebas de widget. Cuando no es `nulo`,
  /// [checkForUpdate] lo devuelve tal cual sin tocar la red ni la caché, de
  /// modo que el kill switch puede ejercitarse de forma determinista.
  @visibleForTesting
  static InutilReleaseInfo? testReleaseOverride;

  Map<String, String> _headers() {
    final idToken = InutilAuthService.instance.currentUser?.idToken;
    return {
      'Content-Type': 'application/json',
      // La API REST de Firestore rechaza la lectura sin una identidad de
      // proyecto (403 PERMISSION_DENIED). La clave pública web del proyecto
      // permite consultar la versión más reciente aunque el dispositivo aún no
      // haya iniciado sesión; el idToken, cuando existe, sigue enviándose para
      // que las reglas de seguridad puedan exigir autenticación en la escritura.
      'X-Goog-Api-Key': FirebaseConfig.apiKey,
      if (idToken != null && idToken.isNotEmpty)
        'Authorization': 'Bearer $idToken',
    };
  }

  /// Consulta la versión más reciente publicada.
  ///
  /// Orden de preferencia:
  /// 1. El manifiesto propio `release.json` (el que Cesar publica junto a los
  ///    binarios; es el que permite publicar una versión sin tocar la consola
  ///    de Firebase).
  /// 2. El documento `app_config/release` de Firestore.
  /// 3. Un PC de la misma red que ya tenga la versión descargada
  ///    (`~/inutil-releases/release.json`, servido en `/api/release`).
  /// 4. La última versión conocida, guardada en la caché local.
  ///
  /// Si nada responde se devuelve la versión instalada (`updateAvailable ==
  /// false`) en lugar de inventar una actualización: así la app nunca promete
  /// un paquete que no puede descargar.
  Future<InutilReleaseInfo> checkForUpdate({String? currentVersion}) async {
    final effectiveCurrent = currentVersion ?? AppConstants.appVersion;

    final pinned = testReleaseOverride;
    if (pinned != null) return pinned;

    final manifest = await _fetchManifestRelease(currentVersion: effectiveCurrent);
    if (manifest != null) {
      await _saveCachedRelease(manifest);
      return manifest;
    }

    try {
      final response = await http
          .get(Uri.parse(_releaseDocumentUrl), headers: _headers())
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final release = _decodeFirestoreRelease(
          decoded,
          currentVersion: effectiveCurrent,
        );
        await _saveCachedRelease(release);
        return release;
      }
    } catch (_) {
      // Sin nube: se intenta la red local y la caché.
    }

    final lan = await _fetchLanRelease(currentVersion: effectiveCurrent);
    if (lan != null) {
      await _saveCachedRelease(lan);
      return lan;
    }

    final cached = await _loadCachedRelease(currentVersion: effectiveCurrent);
    if (cached != null) {
      return cached;
    }

    // Nada confirmado: "estás al día" con la versión instalada.
    final offline = InutilReleaseInfo(
      currentVersion: effectiveCurrent,
      latestVersion: effectiveCurrent,
      releaseNotes: const <String>[],
      mandatory: false,
      publishedAt: DateTime.now().toUtc(),
    );
    return offline;
  }

  /// Manifiesto explícito (`release.json`): URL guardada en Ajustes, variable
  /// de entorno o la ubicación por defecto del bucket de releases.
  Future<InutilReleaseInfo?> _fetchManifestRelease({
    required String currentVersion,
  }) async {
    final candidates = <String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final custom = (prefs.getString(_manifestUrlPrefKey) ?? '').trim();
      if (custom.isNotEmpty) candidates.add(custom);
    } catch (_) {}
    final override = _manifestUrlOverride;
    if (override != null) candidates.add(override);
    // GitHub Releases: asset `release.json` de la última versión publicada.
    if (!FirebaseConfig.useEmulator) candidates.add(_githubManifestUrl);
    candidates.add(_defaultManifestUrl);

    for (final url in candidates) {
      final release = await _fetchReleaseFromUrl(url, currentVersion: currentVersion);
      if (release != null) return release;
    }
    return null;
  }

  Future<InutilReleaseInfo?> _fetchReleaseFromUrl(
    String url, {
    required String currentVersion,
  }) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return _releaseFromRaw(decoded, currentVersion: currentVersion);
    } catch (_) {
      return null;
    }
  }

  /// Versión publicada por un PC de la misma red (misma cuenta).
  Future<InutilReleaseInfo?> _fetchLanRelease({
    required String currentVersion,
  }) async {
    final manifest =
        await InutilPlaybackSyncService.instance.fetchReleaseManifestFromPeers();
    if (manifest == null) return null;
    return _releaseFromRaw(manifest, currentVersion: currentVersion);
  }

  /// Acepta tanto JSON plano (`release.json`) como la respuesta REST de
  /// Firestore (`{"fields": {...}}`).
  InutilReleaseInfo _releaseFromRaw(
    Map<String, dynamic> raw, {
    required String currentVersion,
  }) {
    if (raw['fields'] is Map<String, dynamic>) {
      return _decodeFirestoreRelease(raw, currentVersion: currentVersion);
    }
    return InutilReleaseInfo.fromJson(raw, currentVersionOverride: currentVersion);
  }

  /// URL de manifiesto configurada por el usuario (vacía = la por defecto).
  Future<String> manifestUrlSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getString(_manifestUrlPrefKey) ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> setManifestUrlSetting(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clean = url.trim();
      if (clean.isEmpty) {
        await prefs.remove(_manifestUrlPrefKey);
      } else {
        await prefs.setString(_manifestUrlPrefKey, clean);
      }
    } catch (_) {}
  }

  /// Permite al SuperAdmin César publicar una nueva versión en Firestore
  /// para todos los dispositivos conectados a Inútil Music.
  Future<bool> publishRelease({
    required String version,
    required List<String> notes,
    String apkUrl = '',
    String linuxUrl = '',
    bool mandatory = false,
    String minSupportedVersion = '',
  }) async {
    final cleanVersion = version.trim().isEmpty ? '2.0.0' : version.trim();
    final cleanMin = minSupportedVersion.trim();
    final cleanNotes = notes
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList(growable: false);
    final publishedAt = DateTime.now().toUtc();

    final releaseInfo = InutilReleaseInfo(
      currentVersion: AppConstants.appVersion,
      latestVersion: cleanVersion,
      releaseNotes: cleanNotes.isEmpty
          ? InutilReleaseInfo._defaultCinemaReleaseNotes
          : cleanNotes,
      apkDownloadUrl: apkUrl.trim(),
      linuxDownloadUrl: linuxUrl.trim(),
      mandatory: mandatory,
      minSupportedVersion: cleanMin,
      publishedAt: publishedAt,
    );

    await _saveCachedRelease(releaseInfo);

    final firestoreBody = {
      'fields': {
        'latestVersion': {'stringValue': releaseInfo.latestVersion},
        'apkDownloadUrl': {'stringValue': releaseInfo.apkDownloadUrl},
        'linuxDownloadUrl': {'stringValue': releaseInfo.linuxDownloadUrl},
        'mandatory': {'booleanValue': releaseInfo.mandatory},
        if (cleanMin.isNotEmpty)
          'minSupportedVersion': {'stringValue': cleanMin},
        'publishedAt': {'timestampValue': publishedAt.toIso8601String()},
        'releaseNotes': {
          'arrayValue': {
            'values': [
              for (final note in releaseInfo.releaseNotes)
                {'stringValue': note},
            ],
          },
        },
      },
    };

    try {
      final response = await http
          .patch(
            Uri.parse(_releaseDocumentUrl),
            headers: _headers(),
            body: jsonEncode(firestoreBody),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Descarga el paquete de actualización (`.apk` o `.tar.gz`) a `Directory.systemTemp`
  /// reportando progreso en tiempo real y abre el instalador o carpeta al concluir.
  Future<String> downloadUpdate(
    InutilReleaseInfo release, {
    required void Function(int received, int total) onProgress,
  }) async {
    final url = release.platformDownloadUrl;
    if (url.isEmpty) {
      throw const FormatException(
        'No hay un enlace de descarga directa configurado para esta versión.',
      );
    }

    final uri = Uri.parse(url);
    final isLinuxArchive =
        Platform.isLinux || url.toLowerCase().endsWith('.tar.gz');
    final extension = isLinuxArchive ? '.tar.gz' : '.apk';
    final sanitizedVersion = release.latestVersion.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final fileName = 'inutil_music_v$sanitizedVersion$extension';
    final targetPath = p.join(Directory.systemTemp.path, fileName);
    final file = File(targetPath);

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'InutilMusic-Updater/${AppConstants.appVersion}',
      );
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'El servidor devolvió el código HTTP ${response.statusCode}.',
          uri: uri,
        );
      }

      final totalBytes = response.contentLength;
      var receivedBytes = 0;
      final sink = file.openWrite();

      try {
        await for (final chunk in response) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          onProgress(receivedBytes, totalBytes);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      await _openDownloadedArtifact(file, fallbackUrl: uri);
      return file.path;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _openDownloadedArtifact(
    File downloadedFile, {
    required Uri fallbackUrl,
  }) async {
    if (Platform.isLinux &&
        downloadedFile.path.toLowerCase().endsWith('.tar.gz')) {
      final scheduled = await _installLinuxArchiveAndRelaunch(downloadedFile);
      if (scheduled) return;
    }
    try {
      if (Platform.isLinux) {
        await Process.run('xdg-open', [downloadedFile.parent.path]);
        return;
      }
      final fileUri = Uri.file(downloadedFile.path);
      final opened = await launchUrl(
        fileUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  /// Instala el `.tar.gz` descrito por `InutilReleaseInfo.linuxDownloadUrl`
  /// reemplantando el bundle en ejecución y reiniciando la aplicación.
  ///
  /// El proceso en curso no puede sobrescribir sus propios binarios de forma
  /// fiable, así que se prepara un directorio auxiliar con el contenido nuevo y
  /// se lanza un script desacoplado que espera a que este proceso termine,
  /// sincroniza los archivos sobre el directorio de instalación y vuelve a
  /// abrir Inútil Music. Devuelve `true` cuando la instalación quedó programada,
  /// lo que indica a la interfaz que puede cerrar la aplicación.
  Future<bool> _installLinuxArchiveAndRelaunch(File archive) async {
    final executable = File(Platform.resolvedExecutable);
    final installRoot = executable.parent;
    final executableName = executable.uri.pathSegments.last;
    if (!installRoot.existsSync() || executableName.isEmpty) return false;

    final staging = await Directory.systemTemp.createTemp('inutil_update_');
    final extracted = await Process.run('tar', [
      '-xzf',
      archive.path,
      '-C',
      staging.path,
    ]);
    final stagedExecutable = File(p.join(staging.path, executableName));
    if (extracted.exitCode != 0 || !stagedExecutable.existsSync()) {
      await staging.delete(recursive: true).catchError((_) => staging);
      return false;
    }

    final launcher = File(p.join(installRoot.path, executableName));
    final helper = File(p.join(staging.path, 'inutil_update_apply.sh'));
    await helper.writeAsString(
      r'''#!/bin/sh
# Aplicación diferida de la actualización de Inútil Music.
# argv: <pid que debe terminar> <staging> <directorio de instalación> <ejecutable>
set -u
PID="$1"; STAGING="$2"; DEST="$3"; EXEC="$4"
while kill -0 "$PID" 2>/dev/null; do
  sleep 0.3
done
cp -a "$STAGING/." "$DEST/"
# data/ y lib/ son payload puro del paquete: todo lo que la versión nueva ya no
# incluye se retira, para no arrastrar .so obsoletos. Lo demás (datos del
# usuario) se conserva intacto.
for dir in data lib; do
  [ -d "$STAGING/$dir" ] || continue
  [ -d "$DEST/$dir" ] || continue
  find "$DEST/$dir" -mindepth 1 -maxdepth 1 | while read -r old; do
    base=$(basename "$old")
    [ -e "$STAGING/$dir/$base" ] || rm -rf "$old"
  done
done
# El propio helper vive en staging: no debe quedar instalado.
rm -f "$DEST/inutil_update_apply.sh"
chmod +x "$EXEC"
rm -rf "$STAGING"
"$EXEC" >/dev/null 2>&1 &
''',
    );
    await Process.run('chmod', ['+x', helper.path]);

    await Process.start(
      '/bin/sh',
      [helper.path, '$pid', staging.path, installRoot.path, launcher.path],
      mode: ProcessStartMode.detached,
    );
    return true;
  }

  InutilReleaseInfo _decodeFirestoreRelease(
    Map<String, dynamic> doc, {
    required String currentVersion,
  }) {
    final fields = doc['fields'] as Map<String, dynamic>? ?? const {};

    String readString(String key, [String fallback = '']) {
      final field = fields[key] as Map<String, dynamic>?;
      return (field?['stringValue'] as String?)?.trim() ?? fallback;
    }

    bool readBool(String key) {
      final field = fields[key] as Map<String, dynamic>?;
      return field?['booleanValue'] as bool? ?? false;
    }

    int? readInt(String key) {
      final field = fields[key] as Map<String, dynamic>?;
      final raw = field?['integerValue'] ?? field?['doubleValue'];
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString().trim() ?? '');
    }

    DateTime readTimestamp(String key) {
      final field = fields[key] as Map<String, dynamic>?;
      final raw =
          (field?['timestampValue'] ?? field?['stringValue'])?.toString() ?? '';
      return DateTime.tryParse(raw) ?? DateTime.utc(2026, 11, 16);
    }

    List<String> readStringList(String key) {
      final field = fields[key] as Map<String, dynamic>?;
      final arrayVal = field?['arrayValue'] as Map<String, dynamic>?;
      final values = arrayVal?['values'] as List?;
      if (values == null) return const [];
      final list = <String>[];
      for (final item in values) {
        if (item is Map<String, dynamic>) {
          final text = (item['stringValue'] as String?)?.trim() ?? '';
          if (text.isNotEmpty) list.add(text);
        }
      }
      return list;
    }

    final latestVersion = readString('latestVersion', '2.0.0');
    final notes = readStringList('releaseNotes');
    final downloads = InutilReleaseInfo._parseAndroidDownloads(
      fields['androidDownloads'],
    );
    final defaultSize =
        readInt('packageSizeBytes') ??
        readInt('apkSizeBytes') ??
        readInt('androidPackageSizeBytes') ??
        downloads.sizes['universal'] ??
        0;

    return InutilReleaseInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion.isEmpty ? '2.0.0' : latestVersion,
      releaseNotes: notes.isEmpty
          ? InutilReleaseInfo._defaultCinemaReleaseNotes
          : notes,
      apkDownloadUrl: readString('apkDownloadUrl'),
      linuxDownloadUrl: readString('linuxDownloadUrl'),
      mandatory: readBool('mandatory'),
      minSupportedVersion: readString('minSupportedVersion'),
      publishedAt: readTimestamp('publishedAt'),
      androidDownloads: downloads.urls,
      androidDownloadSizes: downloads.sizes,
      androidPackageSizeBytes: defaultSize,
    );
  }

  Future<void> _saveCachedRelease(InutilReleaseInfo release) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsCacheKey, jsonEncode(release.toJson()));
    } catch (_) {}
  }

  Future<InutilReleaseInfo?> _loadCachedRelease({
    required String currentVersion,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return InutilReleaseInfo.fromJson(
        map,
        currentVersionOverride: currentVersion,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Muestra el diálogo modal de actualización de Inútil Music integrado con el
/// tema nativo de la app.
Future<void> showInutilUpdateDialog(
  BuildContext context,
  InutilReleaseInfo release,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !release.effectiveMandatory,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: InutilUpdateDialogContent(release: release),
      );
    },
  );
}

/// Filtra notas internas/técnicas (Firebase, Firestore, admin, licencias, etc.)
/// para que el usuario final solo vea novedades orientadas a su experiencia.
List<String> _userFacingReleaseNotes(List<String> notes) {
  final internalPattern = RegExp(
    r'\b(firebase|firestore|admin|superadmin|licencia|licencias|keystore|commit|ota|kill\s*switch|rebrand|cinema\s*edition|storage|bucket)\b',
    caseSensitive: false,
  );
  final filtered = notes
      .map((n) => n.trim())
      .where((n) => n.isNotEmpty && !internalPattern.hasMatch(n))
      .toList(growable: false);
  if (filtered.isNotEmpty) return filtered;
  return const [
    'Mejoras de rendimiento, estabilidad y reproducción fluida.',
    'Optimizaciones visuales y correcciones generales.',
  ];
}

/// Cuerpo del diálogo de actualización (tarjeta con novedades, progreso de
/// descarga y botones siempre visibles y accesibles). Es público porque
/// [InutilUpdateGate] lo reutiliza cuando la actualización es obligatoria.
class InutilUpdateDialogContent extends StatefulWidget {
  const InutilUpdateDialogContent({super.key, required this.release});

  final InutilReleaseInfo release;

  @override
  State<InutilUpdateDialogContent> createState() =>
      _InutilUpdateDialogWidgetState();
}

class _InutilUpdateDialogWidgetState extends State<InutilUpdateDialogContent> {
  bool _downloading = false;
  int _receivedBytes = 0;
  int _totalBytes = -1;
  String? _downloadedPath;
  String? _error;

  Future<void> _startDownload() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _receivedBytes = 0;
      _totalBytes = -1;
      _downloadedPath = null;
      _error = null;
    });

    try {
      final path = await InutilUpdateService.instance.downloadUpdate(
        widget.release,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _receivedBytes = received;
            _totalBytes = total;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadedPath = path;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error =
            'No se pudo descargar la actualización en este momento. Verifica tu conexión e inténtalo de nuevo.';
      });
    }
  }

  String _formatMegabytes(int bytes) {
    if (bytes <= 0) return '0.0 MB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final release = widget.release;
    final hasUpdate = release.updateAvailable;
    final visibleNotes = _userFacingReleaseNotes(release.releaseNotes);
    final fraction = _totalBytes > 0
        ? (_receivedBytes / _totalBytes).clamp(0.0, 1.0)
        : null;
    final maxDialogHeight = MediaQuery.sizeOf(context).height * 0.72;

    return PopScope(
      canPop: !release.effectiveMandatory && !_downloading,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: maxDialogHeight),
        child: Material(
          color: colors.surfaceContainerHigh,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: release.belowMinSupported
                          ? colors.errorContainer
                          : colors.primaryContainer,
                      foregroundColor: release.belowMinSupported
                          ? colors.onErrorContainer
                          : colors.onPrimaryContainer,
                      child: Icon(
                        hasUpdate
                            ? Icons.system_update_alt_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            release.belowMinSupported
                                ? 'Actualización requerida'
                                : hasUpdate
                                ? 'Actualización disponible'
                                : 'Tu app está actualizada',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: release.belowMinSupported
                                  ? colors.error
                                  : colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hasUpdate
                                ? 'Versión ${release.latestVersion} disponible · Tienes v${release.currentVersion}'
                                : 'Inútil Music v${release.currentVersion}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (hasUpdate)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.cardSurfaceFor(context),
                              borderRadius: BorderRadius.circular(appCardRadius),
                              border: Border.all(
                                color: colors.outlineVariant.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Novedades',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                for (final note in visibleNotes)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(top: 3),
                                          child: Icon(
                                            Icons.check_rounded,
                                            color: colors.primary,
                                            size: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            note,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(height: 1.35),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          )
                        else
                          Text(
                            'Ya cuentas con la versión más reciente de Inútil Music.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        if (_downloading) ...[
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              minHeight: 7,
                              value: fraction,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _totalBytes > 0
                                ? 'Descargando: ${_formatMegabytes(_receivedBytes)} / ${_formatMegabytes(_totalBytes)}'
                                : 'Descargando: ${_formatMegabytes(_receivedBytes)}...',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (_downloadedPath != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer.withValues(
                                alpha: 0.45,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Actualización descargada y lista para instalar.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.errorContainer.withValues(
                                alpha: 0.65,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _error!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!release.effectiveMandatory && !_downloading)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(hasUpdate ? 'Más tarde' : 'Aceptar'),
                      ),
                    if (hasUpdate && release.platformDownloadUrl.isNotEmpty) ...[
                      if (!release.effectiveMandatory && !_downloading)
                        const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _downloading ? null : _startDownload,
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(
                          _downloading
                              ? 'Descargando...'
                              : 'Actualizar v${release.latestVersion}',
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Diálogo exclusivo para el SuperAdmin César que permite publicar una nueva
/// versión OTA en Firestore (`app_config/release`) para todos los usuarios.
Future<void> showInutilAdminPublishUpdateDialog(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Publicar Actualización OTA',
    barrierColor: Colors.black.withValues(alpha: 0.8),
    transitionDuration: InutilDesignSystem.durationNormal,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(InutilDesignSystem.spaceMd),
          child: _InutilAdminPublishUpdateModal(),
        ),
      );
    },
  );
}

class _InutilAdminPublishUpdateModal extends StatefulWidget {
  const _InutilAdminPublishUpdateModal();

  @override
  State<_InutilAdminPublishUpdateModal> createState() =>
      _InutilAdminPublishUpdateModalState();
}

class _InutilAdminPublishUpdateModalState
    extends State<_InutilAdminPublishUpdateModal> {
  final TextEditingController _versionController = TextEditingController(
    text: '2.1.0',
  );
  final TextEditingController _apkUrlController = TextEditingController();
  final TextEditingController _linuxUrlController = TextEditingController();

  /// Kill switch: versiones instaladas por debajo de este valor quedan
  /// inhabilitadas y su diálogo de actualización no se puede descartar.
  final TextEditingController _minVersionController = TextEditingController();
  final TextEditingController _notesController = TextEditingController(
    text:
        'Mejoras de rendimiento y estabilidad en Inútil Music.\n'
        'Sincronización instantánea de playlists y favoritos en la nube.',
  );
  bool _mandatory = false;
  bool _publishing = false;
  String? _statusMessage;
  bool _publishedSuccess = false;

  @override
  void dispose() {
    _versionController.dispose();
    _apkUrlController.dispose();
    _linuxUrlController.dispose();
    _minVersionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_publishing) return;
    setState(() {
      _publishing = true;
      _statusMessage = null;
    });

    final notes = _notesController.text
        .split(RegExp(r'[\r\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final ok = await InutilUpdateService.instance.publishRelease(
      version: _versionController.text,
      notes: notes,
      apkUrl: _apkUrlController.text,
      linuxUrl: _linuxUrlController.text,
      mandatory: _mandatory,
      minSupportedVersion: _minVersionController.text,
    );

    if (!mounted) return;
    setState(() {
      _publishing = false;
      _publishedSuccess = ok;
      _statusMessage = ok
          ? 'Versión v${_versionController.text.trim()} publicada globalmente en Firestore.'
          : 'Guardada en caché local (verifica permisos o red de Firestore).';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: InutilDesignSystem.borderXl,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(InutilDesignSystem.spaceLg),
            decoration: InutilDesignSystem.glowCardDecoration(
              accentColor: InutilDesignSystem.secondaryGlow,
              radius: InutilDesignSystem.radiusXl,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.rocket_launch_rounded,
                        color: InutilDesignSystem.secondaryGlow,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Publicar Actualización OTA (SuperAdmin)',
                          style: TextStyle(
                            color: InutilDesignSystem.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: InutilDesignSystem.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: InutilDesignSystem.spaceMd),
                  _buildField(
                    controller: _versionController,
                    label: 'Nueva Versión (SemVer)',
                    hint: '2.1.0',
                  ),
                  const SizedBox(height: InutilDesignSystem.spaceSm),
                  _buildField(
                    controller: _apkUrlController,
                    label: 'URL de descarga APK (Android)',
                    hint: 'https://.../inutil_music.apk',
                  ),
                  const SizedBox(height: InutilDesignSystem.spaceSm),
                  _buildField(
                    controller: _linuxUrlController,
                    label: 'URL de descarga Linux (.tar.gz)',
                    hint: 'https://.../inutil_music_linux.tar.gz',
                  ),
                  const SizedBox(height: InutilDesignSystem.spaceSm),
                  _buildField(
                    controller: _minVersionController,
                    label: 'Versión mínima soportada (kill switch)',
                    hint: 'ej. 2.1.0 — deja inoperables las versiones anteriores',
                  ),
                  const SizedBox(height: InutilDesignSystem.spaceSm),
                  _buildField(
                    controller: _notesController,
                    label: 'Notas de lanzamiento (una por línea)',
                    maxLines: 4,
                  ),
                  const SizedBox(height: InutilDesignSystem.spaceSm),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _mandatory,
                    activeTrackColor: InutilDesignSystem.secondaryGlow,
                    title: const Text(
                      'Actualización obligatoria',
                      style: TextStyle(
                        color: InutilDesignSystem.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Exige actualizar la app antes de continuar usándola',
                      style: TextStyle(
                        color: InutilDesignSystem.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    onChanged: (val) => setState(() => _mandatory = val),
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(height: InutilDesignSystem.spaceSm),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (_publishedSuccess
                                ? InutilDesignSystem.accentCyan
                                : InutilDesignSystem.secondaryGlow)
                            .withValues(alpha: 0.15),
                        borderRadius: InutilDesignSystem.borderMd,
                      ),
                      child: Text(
                        _statusMessage!,
                        style: const TextStyle(
                          color: InutilDesignSystem.textPrimary,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: InutilDesignSystem.spaceMd),
                  FilledButton.icon(
                    onPressed: _publishing ? null : _publish,
                    style: FilledButton.styleFrom(
                      backgroundColor: InutilDesignSystem.secondaryGlow,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: InutilDesignSystem.borderMd,
                      ),
                    ),
                    icon: const Icon(Icons.cloud_upload_rounded, size: 19),
                    label: Text(
                      _publishing
                          ? 'Publicando en Firestore...'
                          : 'Publicar Versión Ahora',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(
        color: InutilDesignSystem.textPrimary,
        fontSize: 13,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(
          color: InutilDesignSystem.textSecondary,
          fontSize: 12,
        ),
        hintStyle: const TextStyle(
          color: InutilDesignSystem.textMuted,
          fontSize: 12,
        ),
        filled: true,
        fillColor: InutilDesignSystem.backgroundCarbon,
        enabledBorder: OutlineInputBorder(
          borderRadius: InutilDesignSystem.borderMd,
          borderSide: const BorderSide(color: InutilDesignSystem.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: InutilDesignSystem.borderMd,
          borderSide: const BorderSide(
            color: InutilDesignSystem.secondaryGlow,
          ),
        ),
      ),
    );
  }
}

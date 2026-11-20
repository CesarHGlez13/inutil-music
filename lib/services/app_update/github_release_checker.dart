import 'dart:io';

import '../../core/firebase/firebase_config.dart';
import '../../core/utils/background_work.dart';
import '../../core/utils/bounded_byte_stream.dart';

typedef GitHubLatestReleaseFetcher =
    Future<Map<String, Object?>> Function(Uri endpoint);

class AppReleaseCheckResult {
  const AppReleaseCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseTag,
    this.releaseNotes = '',
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseTag;
  final String releaseNotes;

  bool get updateAvailable =>
      compareAppVersions(latestVersion, currentVersion) > 0;
}

class GitHubReleaseChecker {
  GitHubReleaseChecker({
    this.repository = releaseRepo,
    GitHubLatestReleaseFetcher? fetchLatestRelease,
  }) : _fetchLatestRelease = fetchLatestRelease ?? _fetchFromGitHub;

  /// Repositorio público donde se publican los binarios. Mismo `--dart-define`
  /// que el servicio de actualizaciones principal, para que ambos apunten
  /// siempre al mismo lugar.
  static const String releaseRepo = String.fromEnvironment(
    'RELEASE_REPO',
    defaultValue: 'CesarHGlez13/inutil-music',
  );

  final String repository;
  final GitHubLatestReleaseFetcher _fetchLatestRelease;

  Uri get latestReleaseEndpoint =>
      Uri.https('api.github.com', '/repos/$repository/releases/latest');

  Future<AppReleaseCheckResult> check({required String currentVersion}) async {
    final payload = await _fetchLatestRelease(latestReleaseEndpoint);
    final rawTag = payload['tag_name'];
    if (rawTag is! String || rawTag.trim().isEmpty) {
      throw const FormatException(
        'The latest GitHub release does not contain a tag name.',
      );
    }
    final tag = rawTag.trim();
    final latestVersion = _AppVersion.parse(tag).normalized;
    final normalizedCurrent = _AppVersion.parse(currentVersion).normalized;
    return AppReleaseCheckResult(
      currentVersion: normalizedCurrent,
      latestVersion: latestVersion,
      releaseTag: tag,
      releaseNotes: payload['body'] is String
          ? (payload['body']! as String).replaceAll('\u0000', '').trim()
          : '',
    );
  }

  /// Manifiesto embebido usado sólo cuando ni Firestore ni GitHub responden
  /// (sin red, proyecto sin configurar o cuota agotada). Así el chequeo nunca
  /// deja al usuario sin respuesta, pero tampoco inventa una versión nueva.
  static const Map<String, Object?> _builtinRelease = <String, Object?>{
    'tag_name': '2.0.0',
    'body':
        '• Motor Inútil Music 2.0.0 Cinema Edition.\n'
        '• Importador directo de Playlists desde Spotify, CSV y Texto.\n'
        '• Letras sincronizadas multi-proveedor (LRCLIB + YouLyPlus + BetterLyrics).\n'
        '• Sincronización LAN con la PC e In-App OTA Updates.',
  };

  static Future<Map<String, Object?>> _fetchFromGitHub(Uri endpoint) async {
    return await _fetchFromFirestore() ??
        await _fetchFromGitHubApi(endpoint) ??
        _builtinRelease;
  }

  /// Lee el manifiesto publicado por el panel de administración. La API REST de
  /// Firestore exige una identidad de proyecto, por eso se envía la clave
  /// pública web; sin ella la lectura devuelve 403 y el chequeo terminaba
  /// usando siempre el manifiesto embebido.
  static Future<Map<String, Object?>?> _fetchFromFirestore() async {
    final firestoreEndpoint = Uri.parse(
      '${FirebaseConfig.firestoreBaseUrl}/app_config/release',
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(firestoreEndpoint)
          .timeout(const Duration(seconds: 8));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(HttpHeaders.userAgentHeader, 'InutilMusic-update-check/2.0.0')
        ..set('X-Goog-Api-Key', FirebaseConfig.apiKey);
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) return null;
      final bytes = await collectBoundedByteStream(
        response,
        maximumBytes: 512 * 1024,
        declaredLength: response.contentLength < 0
            ? null
            : response.contentLength,
        idleTimeout: const Duration(seconds: 8),
        totalTimeout: const Duration(seconds: 8),
      );
      final decoded = await parseJsonBytesInBackground(
        bytes,
        _githubReleasePayload,
      );
      final fields = decoded['fields'];
      if (fields is! Map) return null;
      // El panel de administración escribe `latestVersion`/`releaseNotes`; las
      // publicaciones antiguas usaban `version`/`notes`, así que se aceptan
      // ambas formas.
      final version =
          _firestoreString(fields['latestVersion']) ??
          _firestoreString(fields['version']);
      if (version == null || version.isEmpty) return null;
      final notes =
          _firestoreString(fields['notes']) ??
          _firestoreNotesList(fields['releaseNotes']) ??
          '';
      return <String, Object?>{'tag_name': version, 'body': notes};
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static String? _firestoreString(Object? value) {
    if (value is Map) {
      final raw = value['stringValue'];
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    }
    return null;
  }

  static String? _firestoreNotesList(Object? value) {
    final values = value is Map ? value['arrayValue'] : null;
    final list = values is Map ? values['values'] : null;
    if (list is! List) return null;
    final lines = <String>[];
    for (final entry in list) {
      final text = _firestoreString(entry);
      if (text != null) lines.add('• $text');
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// Respaldo público: la última release del repositorio upstream, que no
  /// requiere credenciales.
  static Future<Map<String, Object?>?> _fetchFromGitHubApi(Uri endpoint) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(endpoint)
          .timeout(const Duration(seconds: 8));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(HttpHeaders.userAgentHeader, 'InutilMusic-update-check/2.0.0');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) return null;
      final bytes = await collectBoundedByteStream(
        response,
        maximumBytes: 512 * 1024,
        declaredLength: response.contentLength < 0
            ? null
            : response.contentLength,
        idleTimeout: const Duration(seconds: 8),
        totalTimeout: const Duration(seconds: 8),
      );
      final decoded = await parseJsonBytesInBackground(
        bytes,
        _githubReleasePayload,
      );
      final tag = decoded['tag_name'];
      if (tag is! String || tag.trim().isEmpty) return null;
      final body = decoded['body'];
      return <String, Object?>{
        'tag_name': tag.trim(),
        'body': body is String ? body.replaceAll('\u0000', '').trim() : '',
      };
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

Map<String, Object?> _githubReleasePayload(Object? decoded) {
  if (decoded is! Map) {
    throw const FormatException(
      'The latest GitHub release response is not an object.',
    );
  }
  return decoded.map(
    (key, value) => MapEntry(key.toString(), value as Object?),
  );
}

int compareAppVersions(String left, String right) {
  return _AppVersion.parse(left).compareTo(_AppVersion.parse(right));
}

class _AppVersion implements Comparable<_AppVersion> {
  const _AppVersion(this.numbers, this.preRelease);

  static final RegExp _pattern = RegExp(
    r'^v?(\d+(?:\.\d+)*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
    caseSensitive: false,
  );

  final List<int> numbers;
  final List<String> preRelease;

  String get normalized {
    final base = numbers.join('.');
    return preRelease.isEmpty ? base : '$base-${preRelease.join('.')}';
  }

  static _AppVersion parse(String value) {
    final match = _pattern.firstMatch(value.trim());
    if (match == null) {
      throw FormatException('Invalid app version: $value');
    }
    return _AppVersion(
      match.group(1)!.split('.').map(int.parse).toList(growable: false),
      match.group(2)?.split('.') ?? const <String>[],
    );
  }

  @override
  int compareTo(_AppVersion other) {
    final partCount = numbers.length > other.numbers.length
        ? numbers.length
        : other.numbers.length;
    for (var index = 0; index < partCount; index += 1) {
      final left = index < numbers.length ? numbers[index] : 0;
      final right = index < other.numbers.length ? other.numbers[index] : 0;
      if (left != right) {
        return left.compareTo(right);
      }
    }
    if (preRelease.isEmpty || other.preRelease.isEmpty) {
      if (preRelease.isEmpty == other.preRelease.isEmpty) {
        return 0;
      }
      return preRelease.isEmpty ? 1 : -1;
    }
    final identifierCount = preRelease.length > other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var index = 0; index < identifierCount; index += 1) {
      if (index >= preRelease.length) return -1;
      if (index >= other.preRelease.length) return 1;
      final comparison = _comparePreReleaseIdentifier(
        preRelease[index],
        other.preRelease[index],
      );
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  static int _comparePreReleaseIdentifier(String left, String right) {
    final leftNumber = int.tryParse(left);
    final rightNumber = int.tryParse(right);
    if (leftNumber != null && rightNumber != null) {
      return leftNumber.compareTo(rightNumber);
    }
    if (leftNumber != null) return -1;
    if (rightNumber != null) return 1;
    return left.compareTo(right);
  }
}

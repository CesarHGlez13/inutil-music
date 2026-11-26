import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Progreso de una descarga OTA.
///
/// [receivedBytes] siempre es el total acumulado en disco (incluye lo
/// recuperado de una sesión anterior), de modo que la barra de progreso de la
/// interfaz no retrocede al reanudar.
class OtaDownloadProgress {
  const OtaDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.resumedBytes,
    required this.bytesPerSecond,
  });

  final int receivedBytes;

  /// Tamaño total esperado, o `-1` cuando el servidor no lo informa.
  final int totalBytes;

  /// Bytes que ya estaban en el archivo `.part` al empezar esta sesión.
  final int resumedBytes;

  /// Velocidad medida de esta sesión (no incluye lo reanudado).
  final int bytesPerSecond;

  bool get hasTotal => totalBytes > 0;

  double? get fraction {
    if (totalBytes <= 0) return null;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get isResuming => resumedBytes > 0;
}

/// Cancelación cooperativa de una descarga OTA iniciada por el usuario.
class OtaDownloadCancelled implements Exception {
  const OtaDownloadCancelled();

  @override
  String toString() => 'La descarga de la actualización se canceló.';
}

/// Error de red o de servidor durante la descarga del paquete.
class OtaDownloadException implements Exception {
  const OtaDownloadException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Descarga el paquete de actualización con reanudación y sin servicios de
/// Android.
///
/// Decisión de diseño (requisito «sin notificación persistente»):
/// la descarga NO usa `flutter_background_service` ni `flutter_local_notifications`.
/// `flutter_background_service` arranca un `ForegroundService`, y Android sólo
/// permite mantenerlo con una notificación `ongoing: true` más un
/// `foregroundServiceType`; eso es exactamente la notificación persistente que
/// Cesar pidió evitar, y antes de Android 15 no existe un
/// `foregroundServiceType` válido para «descargar archivos». En su lugar la
/// descarga corre en el isolate de la aplicación con `HttpClient`: el proceso
/// de Inutix Music ya está vivo mientras la interfaz está abierta, y si hay
/// audio sonando el servicio `mediaPlayback` de `audio_service` mantiene el
/// proceso despierto aunque la pantalla se apague. El progreso se publica
/// únicamente dentro de la app a través de [OtaDownloadProgress]; no se crea
/// ninguna notificación, ni persistente ni de progreso.
///
/// El archivo se escribe como `<nombre>.part` junto a un sidecar `.meta` con el
/// URL, `ETag` y `Last-Modified` del servidor. Al reanudar se envía
/// `Range: bytes=<descargado>-` sólo si el sidecar confirma que el recurso es
/// el mismo; si el servidor ignora el rango (responde `200`) la descarga
/// empieza de cero en lugar de mezclar dos copias del APK.
class OtaDownloadManager {
  OtaDownloadManager({HttpClient? client, Stopwatch Function()? clock})
    : _httpClient = client,
      _clock = clock ?? Stopwatch.new;

  static const String updatesDirectoryName = 'updates';
  static const Duration _idleTimeout = Duration(seconds: 45);
  static const Duration _connectTimeout = Duration(seconds: 25);
  static const Duration _responseTimeout = Duration(seconds: 30);
  static const Duration _progressThrottle = Duration(milliseconds: 180);
  static const int _progressByteThrottle = 256 * 1024;
  static const int _statusPartialContent = 206;
  static const int _statusRangeNotSatisfiable = 416;

  final HttpClient? _httpClient;

  /// Fabrica del cronómetro de velocidad; se inyecta para pruebas.
  final Stopwatch Function() _clock;

  bool _cancelled = false;
  StreamSubscription<List<int>>? _activeSubscription;
  HttpClient? _ownedClient;

  bool get isDownloadActive => _activeSubscription != null;

  /// Cierra el cliente propio. Un manager compartido puede vivir toda la
  /// sesión, así que esto sólo se llama al desmontar la app en pruebas.
  void dispose() {
    unawaited(_activeSubscription?.cancel() ?? Future<void>.value());
    _activeSubscription = null;
    _ownedClient?.close(force: true);
    _ownedClient = null;
  }

  /// Carpeta privada de la app donde viven los paquetes.
  ///
  /// En Android prioriza `getTemporaryDirectory()/updates` (`cacheDir/updates`,
  /// almacenamiento interno listado en `provider_paths.xml` como `cache-path`),
  /// evitando bloqueos de FUSE/Scoped Storage en `Android/data` en Android 11-15.
  Future<Directory> updatesDirectory() async {
    Directory? base;
    try {
      if (Platform.isAndroid) {
        base = await getTemporaryDirectory();
      } else if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        base = await getApplicationSupportDirectory();
      }
    } catch (_) {
      base = null;
    }
    if (base == null && Platform.isAndroid) {
      try {
        base = await getExternalStorageDirectory();
      } catch (_) {
        base = null;
      }
    }
    base ??= await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(base.path, updatesDirectoryName));
    return directory.create(recursive: true);
  }

  /// Verifica que un archivo `.apk` tenga firma ZIP (`PK\x03\x04`) y, si se
  /// publicó `expectedSha256`, que el hash coincida exactamente.
  Future<String?> _validateDownloadedFile(
    File file, {
    required String fileName,
    String expectedSha256 = '',
  }) async {
    if (!await file.exists()) return 'El archivo descargado no existe.';
    final size = await file.length();
    if (size < 4) return 'El archivo descargado está vacío o truncado.';
    if (fileName.toLowerCase().endsWith('.apk')) {
      RandomAccessFile? raf;
      try {
        raf = await file.open();
        final header = await raf.read(4);
        if (header.length < 4 ||
            header[0] != 0x50 ||
            header[1] != 0x4B ||
            header[2] != 0x03 ||
            header[3] != 0x04) {
          return 'El archivo descargado no es un paquete APK válido (posible bloqueo de red o portal cautivo).';
        }
      } finally {
        await raf?.close();
      }
    }
    final cleanSha = expectedSha256.trim().toLowerCase();
    if (cleanSha.isNotEmpty) {
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString().toLowerCase() != cleanSha) {
        return 'La verificación de integridad (SHA-256) falló; el paquete se descargó corrupto.';
      }
    }
    return null;
  }

  /// Cancela la descarga en curso. El `.part` se conserva para reanudar.
  Future<void> cancelActiveDownload() async {
    _cancelled = true;
    final subscription = _activeSubscription;
    _activeSubscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }
  }

  /// Devuelve la ruta final del paquete si ya estaba descargado e íntegro.
  Future<String?> existingDownload({
    required String url,
    required String fileName,
    String expectedSha256 = '',
  }) async {
    try {
      final directory = await updatesDirectory();
      final finalFile = File(p.join(directory.path, fileName));
      final doneMetaPath = p.join(directory.path, '$fileName.done.meta');
      if (!await finalFile.exists()) return null;
      final meta = await _readMeta(doneMetaPath);
      // Un paquete completo sólo es reaprovechable si pertenece al mismo URL
      // y pasa la validación ZIP + SHA-256; si está dañado se descarta.
      if (meta != null && meta['url'] == url && meta['complete'] == true) {
        final problem = await _validateDownloadedFile(
          finalFile,
          fileName: fileName,
          expectedSha256: expectedSha256,
        );
        if (problem == null) return finalFile.path;
        await _deleteQuietly(finalFile);
        await _deleteQuietly(File(doneMetaPath));
      }
    } catch (_) {}
    return null;
  }

  /// Descarga [url] dentro de [updatesDirectory] y devuelve la ruta final.
  ///
  /// [onProgress] se invoca en el isolate principal con el progreso acumulado.
  Future<String> download({
    required String url,
    required String fileName,
    required void Function(OtaDownloadProgress progress) onProgress,
    String expectedSha256 = '',
  }) async {
    _cancelled = false;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw const OtaDownloadException('El enlace de descarga no es válido.');
    }
    final directory = await updatesDirectory();
    final finalPath = p.join(directory.path, fileName);
    final partPath = p.join(directory.path, '$fileName.part');
    final metaPath = p.join(directory.path, '$fileName.part.meta');
    final doneMetaPath = p.join(directory.path, '$fileName.done.meta');
    final partFile = File(partPath);

    final previous = await existingDownload(
      url: url,
      fileName: fileName,
      expectedSha256: expectedSha256,
    );
    if (previous != null) return previous;

    var startOffset = 0;
    if (await partFile.exists()) {
      final meta = await _readMeta(metaPath);
      if (meta == null || meta['url'] != url) {
        await _deleteQuietly(partFile);
        await _deleteQuietly(File(metaPath));
      } else {
        startOffset = await partFile.length();
      }
    }

    final client =
        _httpClient ??
        (_ownedClient ??= HttpClient()..connectionTimeout = _connectTimeout);

    HttpClientResponse response;
    try {
      final request = await client.getUrl(uri).timeout(_connectTimeout);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'InutilMusic-Updater/2.0.0 (OTA; resumable)',
      );
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      if (startOffset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$startOffset-');
      }
      response = await request.close().timeout(_responseTimeout);
    } on TimeoutException {
      throw const OtaDownloadException(
        'El servidor de actualizaciones tardó demasiado en responder.',
      );
    } on SocketException catch (error) {
      throw OtaDownloadException(
        'No hay conexión con el servidor de actualizaciones: ${error.message}',
      );
    }

    if (response.statusCode == _statusRangeNotSatisfiable) {
      // El `.part` quedó obsoleto (el APK cambió de tamaño). Se descarta y la
      // próxima comprobación descarga el paquete completo.
      await _deleteQuietly(partFile);
      await _deleteQuietly(File(metaPath));
      await response.drain<void>();
      throw const OtaDownloadException(
        'La descarga anterior quedó obsoleta. Vuelve a intentarlo.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw OtaDownloadException(
        'El servidor devolvió el código HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }

    final partialAccepted =
        response.statusCode == _statusPartialContent && startOffset > 0;
    if (!partialAccepted && startOffset > 0) {
      // El servidor ignoró `Range`; continuar escribiendo desde el offset
      // mezclaría dos copias del APK y el instalador rechazaría el paquete.
      await _deleteQuietly(partFile);
      startOffset = 0;
    }

    final remaining = response.contentLength;
    final totalBytes = remaining < 0
        ? -1
        : (partialAccepted ? startOffset + remaining : remaining);

    await _writeMeta(metaPath, <String, Object?>{
      'url': url,
      'etag': response.headers.value(HttpHeaders.etagHeader),
      'lastModified': response.headers.value(HttpHeaders.lastModifiedHeader),
      'totalBytes': totalBytes,
      'complete': false,
    });

    final sink = partFile.openWrite(
      mode: partialAccepted ? FileMode.append : FileMode.write,
    );
    final stopwatch = _clock()..start();
    var sessionBytes = 0;
    var lastEmitBytes = 0;
    var lastEmitAt = DateTime.fromMillisecondsSinceEpoch(0);
    final completer = Completer<String>();
    Timer? idleTimer;

    void reportProgress() {
      final elapsed = stopwatch.elapsed;
      final speed = elapsed.inMilliseconds > 200
          ? sessionBytes * 1000 ~/ elapsed.inMilliseconds
          : 0;
      onProgress(
        OtaDownloadProgress(
          receivedBytes: startOffset + sessionBytes,
          totalBytes: totalBytes,
          resumedBytes: partialAccepted ? startOffset : 0,
          bytesPerSecond: speed,
        ),
      );
      lastEmitBytes = sessionBytes;
      lastEmitAt = DateTime.now();
    }

    void failWith(Object error, [StackTrace? stackTrace]) {
      if (completer.isCompleted) return;
      completer.completeError(error, stackTrace ?? StackTrace.current);
    }

    void armIdleTimer() {
      idleTimer?.cancel();
      idleTimer = Timer(_idleTimeout, () {
        final active = _activeSubscription;
        _activeSubscription = null;
        unawaited(active?.cancel() ?? Future<void>.value());
        unawaited(sink.close());
        failWith(
          const OtaDownloadException(
            'La descarga dejó de responder. Puedes reanudarla.',
          ),
        );
      });
    }

    reportProgress();
    late final StreamSubscription<List<int>> subscription;
    subscription = response.listen(
      (chunk) {
        armIdleTimer();
        sink.add(chunk);
        sessionBytes += chunk.length;
        final sinceBytes = sessionBytes - lastEmitBytes;
        final sinceTime = DateTime.now().difference(lastEmitAt);
        if (sinceBytes >= _progressByteThrottle ||
            sinceTime >= _progressThrottle) {
          reportProgress();
        }
      },
      onDone: () async {
        idleTimer?.cancel();
        _activeSubscription = null;
        try {
          await sink.flush();
          await sink.close();
        } catch (_) {
          // La validación de tamaño decide si el `.part` sigue siendo útil.
        }
        if (_cancelled) {
          failWith(const OtaDownloadCancelled());
          return;
        }
        try {
          final written = await partFile.length();
          if (totalBytes > 0 && written != totalBytes) {
            throw OtaDownloadException(
              'La descarga se interrumpió en $written de $totalBytes bytes. '
              'Vuelve a intentarlo y continuará donde se quedó.',
            );
          }
          final validationProblem = await _validateDownloadedFile(
            partFile,
            fileName: fileName,
            expectedSha256: expectedSha256,
          );
          if (validationProblem != null) {
            await _deleteQuietly(partFile);
            await _deleteQuietly(File(metaPath));
            throw OtaDownloadException(validationProblem);
          }
          final target = File(finalPath);
          if (await target.exists()) {
            await target.delete();
          }
          await partFile.rename(finalPath);
          await _writeMeta(doneMetaPath, <String, Object?>{
            'url': url,
            'etag': response.headers.value(HttpHeaders.etagHeader),
            'lastModified': response.headers.value(
              HttpHeaders.lastModifiedHeader,
            ),
            'totalBytes': written,
            'complete': true,
          });
          await _deleteQuietly(File(metaPath));
          if (!completer.isCompleted) {
            completer.complete(finalPath);
          }
        } catch (error, stackTrace) {
          failWith(error, stackTrace);
        }
      },
      onError: (Object error, StackTrace stackTrace) async {
        idleTimer?.cancel();
        _activeSubscription = null;
        try {
          await sink.close();
        } catch (_) {}
        if (_cancelled) {
          failWith(const OtaDownloadCancelled());
          return;
        }
        failWith(
          error is OtaDownloadException
              ? error
              : OtaDownloadException(
                  'La descarga se interrumpió: $error. '
                  'Puedes reanudarla desde Ajustes.',
                ),
          stackTrace,
        );
      },
      cancelOnError: true,
    );
    _activeSubscription = subscription;
    armIdleTimer();

    try {
      return await completer.future;
    } finally {
      idleTimer?.cancel();
      _activeSubscription = null;
    }
  }

  /// Borra los paquetes descargados para liberar almacenamiento.
  Future<void> clearDownloads() async {
    try {
      final directory = await updatesDirectory();
      if (!await directory.exists()) return;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File) {
          await _deleteQuietly(entity);
        }
      }
    } catch (_) {}
  }

  Future<Map<String, Object?>?> _readMeta(String metaFilePath) async {
    try {
      final file = File(metaFilePath);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writeMeta(
    String metaFilePath,
    Map<String, Object?> meta,
  ) async {
    try {
      final file = File(metaFilePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(meta), flush: true);
    } catch (_) {}
  }

  Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) {
        await entity.delete();
      }
    } catch (_) {}
  }
}

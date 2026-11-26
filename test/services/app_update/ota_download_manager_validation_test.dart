import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/services/app_update/ota_download_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);
  final Directory root;

  @override
  Future<String?> getTemporaryPath() async => root.path;

  @override
  Future<String?> getApplicationSupportPath() async => root.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;

  @override
  Future<String?> getExternalStoragePath() async => root.path;
}

void main() {
  late Directory tempDir;
  late PathProviderPlatform previousProvider;
  late HttpServer server;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ota_validation_test_');
    previousProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TempPathProvider(tempDir);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
    PathProviderPlatform.instance = previousProvider;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('rechaza un .apk que en realidad contiene HTML (portal cautivo) y borra el archivo', () async {
    server.listen((req) {
      final body = utf8.encode('<html><body>Portal cautivo</body></html>');
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = body.length
        ..add(body);
      req.response.close();
    });

    final manager = OtaDownloadManager();
    addTearDown(manager.dispose);

    await expectLater(
      manager.download(
        url: 'http://127.0.0.1:${server.port}/app.apk',
        fileName: 'test_corrupt.apk',
        onProgress: (_) {},
      ),
      throwsA(
        isA<OtaDownloadException>().having(
          (e) => e.message,
          'message',
          contains('no es un paquete APK válido'),
        ),
      ),
    );

    final updatesDir = Directory('${tempDir.path}/updates');
    final files = updatesDir.existsSync() ? updatesDir.listSync() : const [];
    expect(files.where((f) => f.path.endsWith('.apk') || f.path.endsWith('.part')), isEmpty);
  });

  test('rechaza un .apk con SHA-256 distinto al publicado y acepta uno íntegro', () async {
    final validApkBytes = <int>[0x50, 0x4B, 0x03, 0x04, 1, 2, 3, 4, 5, 6];
    final validSha = sha256.convert(validApkBytes).toString();

    server.listen((req) {
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = validApkBytes.length
        ..add(validApkBytes);
      req.response.close();
    });

    final manager = OtaDownloadManager();
    addTearDown(manager.dispose);

    await expectLater(
      manager.download(
        url: 'http://127.0.0.1:${server.port}/app.apk',
        fileName: 'test_sha.apk',
        expectedSha256: '0000000000000000000000000000000000000000000000000000000000000000',
        onProgress: (_) {},
      ),
      throwsA(
        isA<OtaDownloadException>().having(
          (e) => e.message,
          'message',
          contains('SHA-256'),
        ),
      ),
    );

    final path = await manager.download(
      url: 'http://127.0.0.1:${server.port}/app.apk',
      fileName: 'test_sha.apk',
      expectedSha256: validSha,
      onProgress: (_) {},
    );
    expect(File(path).existsSync(), isTrue);
    expect(await File(path).readAsBytes(), validApkBytes);

    // Reutilización en caché con SHA válido devuelve la misma ruta.
    final cached = await manager.existingDownload(
      url: 'http://127.0.0.1:${server.port}/app.apk',
      fileName: 'test_sha.apk',
      expectedSha256: validSha,
    );
    expect(cached, path);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:inutil_music/core/constants/app_constants.dart';
import 'package:inutil_music/core/firebase/inutil_update_service.dart';

void main() {
  group('v2.5.28 — Nuevo logo Monolith iX, marca Inutix Music y OTA Cloudflare Edge', () {
    test('identidad visible consolidada como Inutix Music en constantes y AndroidManifest', () {
      expect(AppConstants.appName, 'Inutix Music');
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('android:label="Inutix Music"'));
    });

    test('activos del logotipo Monolith iX existen en todas las plataformas', () {
      const requiredAssets = <String>[
        'assets/icons/inutil_music_master.png',
        'assets/icons/inutil_icon.png',
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png',
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png',
        'android/app/src/main/res/drawable-nodpi/ic_stat_inutil_music.png',
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png',
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
        'windows/runner/resources/app_icon.ico',
      ];
      for (final path in requiredAssets) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'Falta activo: $path');
        expect(
          file.lengthSync(),
          greaterThan(1000),
          reason: 'Activo vacío o corrupto: $path',
        );
      }
      final bgXml = File(
        'android/app/src/main/res/values/ic_launcher_background.xml',
      ).readAsStringSync();
      expect(bgXml, contains('#0D1016'));
    });

    test('cero rutas personales hardcodeadas ni IPs obsoletas en tool/', () {
      final toolDir = Directory('tool');
      for (final entity in toolDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        final lower = entity.path.toLowerCase();
        if (!lower.endsWith('.py') && !lower.endsWith('.sh')) continue;
        final src = entity.readAsStringSync();
        expect(src, isNot(contains('/home/cesar/')), reason: entity.path);
        expect(src, isNot(contains('192.168.100.23')), reason: entity.path);
      }
    });

    test('InutilUpdateService.otaFallbackUrlFor traduce enlaces GitHub a ota.inutix.com/music', () {
      expect(InutilUpdateService.otaEdgeBaseUrl, 'https://ota.inutix.com');

      expect(
        InutilUpdateService.otaFallbackUrlFor(
          'https://github.com/CesarHGlez13/inutil-music/releases/download/v2.5.28/app-arm64-v8a-release.apk',
        ),
        'https://ota.inutix.com/music/download/v2.5.28/app-arm64-v8a-release.apk',
      );
      expect(
        InutilUpdateService.otaFallbackUrlFor(
          'https://github.com/CesarHGlez13/inutil-music/releases/download/v2.5.28/inutil_music_linux_x64.tar.gz',
        ),
        'https://ota.inutix.com/music/download/v2.5.28/inutil_music_linux_x64.tar.gz',
      );
      expect(
        InutilUpdateService.otaFallbackUrlFor(
          'https://github.com/CesarHGlez13/inutil-music/releases/download/v2.5.28/InutilMusic-2.5.28-linux-amd64.deb',
        ),
        'https://ota.inutix.com/music/download/v2.5.28/InutilMusic-2.5.28-linux-amd64.deb',
      );
      // Enlaces que no son de GitHub Releases no se reescriben.
      expect(
        InutilUpdateService.otaFallbackUrlFor(
          'https://api.inutix.com/custom.apk',
        ),
        isEmpty,
      );
    });
  });
}

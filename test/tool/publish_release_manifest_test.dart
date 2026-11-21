import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/firebase/inutil_update_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'publish_release.sh incluye instaladores de PC en checksums y URLs de plataforma',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'inutil_publish_release_test_',
      );
      addTearDown(() async {
        if (tempRoot.existsSync()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final apkDir = Directory(p.join(tempRoot.path, 'apks'))..createSync();
      final distDir = Directory(p.join(tempRoot.path, 'dist'))..createSync();

      const version = '2.5.15';
      final expectedFiles = <String, File>{
        'app-arm64-v8a-release.apk': File(
          p.join(apkDir.path, 'app-arm64-v8a-release.apk'),
        ),
        'app-armeabi-v7a-release.apk': File(
          p.join(apkDir.path, 'app-armeabi-v7a-release.apk'),
        ),
        'app-x86_64-release.apk': File(
          p.join(apkDir.path, 'app-x86_64-release.apk'),
        ),
        'inutil_music_linux_x64.tar.gz': File(
          p.join(distDir.path, 'inutil_music_linux_x64.tar.gz'),
        ),
        'InutilMusic-$version-Windows-x64-Setup.exe': File(
          p.join(distDir.path, 'InutilMusic-$version-Windows-x64-Setup.exe'),
        ),
        'InutilMusic-$version-linux-amd64.deb': File(
          p.join(distDir.path, 'InutilMusic-$version-linux-amd64.deb'),
        ),
        'InutilMusic-$version-linux-x86_64.rpm': File(
          p.join(distDir.path, 'InutilMusic-$version-linux-x86_64.rpm'),
        ),
        'InutilMusic-$version-macOS-arm64.pkg': File(
          p.join(distDir.path, 'InutilMusic-$version-macOS-arm64.pkg'),
        ),
        'InutilMusic-$version-macOS-x64.pkg': File(
          p.join(distDir.path, 'InutilMusic-$version-macOS-x64.pkg'),
        ),
      };

      final expectedChecksums = <String, String>{};
      for (final entry in expectedFiles.entries) {
        final bytes = utf8.encode('payload-${entry.key}');
        entry.value.writeAsBytesSync(bytes);
        expectedChecksums[entry.key] = sha256.convert(bytes).toString();
      }

      final result = await Process.run(
        'bash',
        ['tool/publish_release.sh', version, '--github', '--dry-run'],
        environment: {
          ...Platform.environment,
          'INUTIL_APK_DIR': apkDir.path,
          'INUTIL_DIST_DIR': distDir.path,
        },
      );

      expect(
        result.exitCode,
        0,
        reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}',
      );

      final stdout = result.stdout.toString();
      const marker = '=== release.json ===\n';
      final start = stdout.indexOf(marker);
      expect(start, greaterThanOrEqualTo(0), reason: stdout);
      final afterMarker = stdout.substring(start + marker.length);
      final end = afterMarker.indexOf('\n(dry-run:');
      final jsonText = (end >= 0 ? afterMarker.substring(0, end) : afterMarker)
          .trim();

      final manifest = jsonDecode(jsonText) as Map<String, dynamic>;
      final checksums = Map<String, dynamic>.from(
        manifest['checksums'] as Map? ?? const {},
      );
      for (final entry in expectedChecksums.entries) {
        expect(
          checksums[entry.key],
          entry.value,
          reason: 'Falta o difiere sha256 de ${entry.key} en checksums',
        );
      }

      const base =
          'https://github.com/CesarHGlez13/inutil-music/releases/download/v$version/';
      expect(
        manifest['windowsDownloadUrl'],
        '${base}InutilMusic-$version-Windows-x64-Setup.exe',
      );
      expect(
        manifest['linuxDownloadUrl'],
        '${base}inutil_music_linux_x64.tar.gz',
      );
      expect(
        manifest['linuxDebDownloadUrl'],
        '${base}InutilMusic-$version-linux-amd64.deb',
      );
      expect(
        manifest['linuxRpmDownloadUrl'],
        '${base}InutilMusic-$version-linux-x86_64.rpm',
      );
      expect(
        manifest['macosArm64DownloadUrl'],
        '${base}InutilMusic-$version-macOS-arm64.pkg',
      );
      expect(
        manifest['macosX64DownloadUrl'],
        '${base}InutilMusic-$version-macOS-x64.pkg',
      );
      expect(
        manifest['macosDownloadUrl'],
        '${base}InutilMusic-$version-macOS-arm64.pkg',
      );

      final androidDownloads = Map<String, dynamic>.from(
        manifest['androidDownloads'] as Map? ?? const {},
      );
      expect(
        androidDownloads.keys,
        unorderedEquals(<String>['arm64_v8a', 'armeabi_v7a', 'x86_64']),
      );

      final parsed = InutilReleaseInfo.fromJson(manifest);
      expect(
        parsed.downloadUrlForPlatform('windows'),
        '${base}InutilMusic-$version-Windows-x64-Setup.exe',
      );
      expect(
        parsed.downloadUrlForPlatform('macos', isArm64: true),
        '${base}InutilMusic-$version-macOS-arm64.pkg',
      );
      expect(
        parsed.downloadUrlForPlatform('macos', isArm64: false),
        '${base}InutilMusic-$version-macOS-x64.pkg',
      );
      expect(
        parsed.downloadUrlForPlatform('linux'),
        '${base}inutil_music_linux_x64.tar.gz',
      );
      expect(
        parsed.downloadUrlForPlatform('android'),
        '${base}app-arm64-v8a-release.apk',
      );
    },
    skip: Platform.isWindows ? 'publish_release.sh requiere bash POSIX' : false,
  );
}

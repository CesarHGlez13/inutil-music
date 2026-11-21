import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/firebase/inutil_update_service.dart';

void main() {
  group('InutilReleaseInfo platform download URL resolution', () {
    final fullRelease = InutilReleaseInfo(
      currentVersion: '2.5.14',
      latestVersion: '2.5.15',
      releaseNotes: const ['Mejoras de escritorio y móvil.'],
      apkDownloadUrl: 'https://example.test/app-arm64-v8a-release.apk',
      linuxDownloadUrl: 'https://example.test/inutil_music_linux_x64.tar.gz',
      linuxDebDownloadUrl:
          'https://example.test/InutilMusic-2.5.15-linux-amd64.deb',
      linuxRpmDownloadUrl:
          'https://example.test/InutilMusic-2.5.15-linux-x86_64.rpm',
      windowsDownloadUrl:
          'https://example.test/InutilMusic-2.5.15-Windows-x64-Setup.exe',
      macosDownloadUrl:
          'https://example.test/InutilMusic-2.5.15-macOS-arm64.pkg',
      macosArm64DownloadUrl:
          'https://example.test/InutilMusic-2.5.15-macOS-arm64.pkg',
      macosX64DownloadUrl:
          'https://example.test/InutilMusic-2.5.15-macOS-x64.pkg',
      publishedAt: DateTime.utc(2026, 11, 21),
      androidDownloads: const {
        'arm64_v8a': 'https://example.test/app-arm64-v8a-release.apk',
        'armeabi_v7a': 'https://example.test/app-armeabi-v7a-release.apk',
        'x86_64': 'https://example.test/app-x86_64-release.apk',
      },
      checksums: const {
        'InutilMusic-2.5.15-Windows-x64-Setup.exe': 'aaa111',
        'InutilMusic-2.5.15-macOS-arm64.pkg': 'bbb222',
      },
    );

    final apkAndLinuxOnly = InutilReleaseInfo(
      currentVersion: '2.5.14',
      latestVersion: '2.5.15',
      releaseNotes: const ['Solo APK y Linux.'],
      apkDownloadUrl: 'https://example.test/app-arm64-v8a-release.apk',
      linuxDownloadUrl: 'https://example.test/inutil_music_linux_x64.tar.gz',
      publishedAt: DateTime.utc(2026, 11, 21),
      androidDownloads: const {
        'arm64_v8a': 'https://example.test/app-arm64-v8a-release.apk',
      },
    );

    test('Windows selecciona el instalador .exe y nunca cae al APK', () {
      expect(
        fullRelease.downloadUrlForPlatform('windows'),
        'https://example.test/InutilMusic-2.5.15-Windows-x64-Setup.exe',
      );
      expect(apkAndLinuxOnly.downloadUrlForPlatform('windows'), isEmpty);
    });

    test('macOS selecciona .pkg por arquitectura y nunca cae al APK', () {
      expect(
        fullRelease.downloadUrlForPlatform('macos', isArm64: true),
        'https://example.test/InutilMusic-2.5.15-macOS-arm64.pkg',
      );
      expect(
        fullRelease.downloadUrlForPlatform('macos', isArm64: false),
        'https://example.test/InutilMusic-2.5.15-macOS-x64.pkg',
      );
      expect(
        apkAndLinuxOnly.downloadUrlForPlatform('macos', isArm64: true),
        isEmpty,
      );
      expect(
        apkAndLinuxOnly.downloadUrlForPlatform('macos', isArm64: false),
        isEmpty,
      );
    });

    test('macOS usa macosDownloadUrl como respaldo si falta la arch', () {
      final genericMac = InutilReleaseInfo(
        currentVersion: '2.5.14',
        latestVersion: '2.5.15',
        releaseNotes: const ['macOS genérico.'],
        apkDownloadUrl: 'https://example.test/app.apk',
        macosDownloadUrl: 'https://example.test/InutilMusic-macOS.pkg',
        publishedAt: DateTime.utc(2026, 11, 21),
      );
      expect(
        genericMac.downloadUrlForPlatform('macos', isArm64: true),
        'https://example.test/InutilMusic-macOS.pkg',
      );
      expect(
        genericMac.downloadUrlForPlatform('macos', isArm64: false),
        'https://example.test/InutilMusic-macOS.pkg',
      );
    });

    test(
      'Linux prefiere tarball/AppImage, luego deb/rpm, y nunca cae al APK',
      () {
        expect(
          fullRelease.downloadUrlForPlatform('linux'),
          'https://example.test/inutil_music_linux_x64.tar.gz',
        );

        final debOnly = InutilReleaseInfo(
          currentVersion: '2.5.14',
          latestVersion: '2.5.15',
          releaseNotes: const ['Solo deb.'],
          apkDownloadUrl: 'https://example.test/app.apk',
          linuxDebDownloadUrl:
              'https://example.test/InutilMusic-2.5.15-linux-amd64.deb',
          publishedAt: DateTime.utc(2026, 11, 21),
        );
        expect(
          debOnly.downloadUrlForPlatform('linux'),
          'https://example.test/InutilMusic-2.5.15-linux-amd64.deb',
        );

        final apkOnly = InutilReleaseInfo(
          currentVersion: '2.5.14',
          latestVersion: '2.5.15',
          releaseNotes: const ['Solo APK.'],
          apkDownloadUrl: 'https://example.test/app.apk',
          publishedAt: DateTime.utc(2026, 11, 21),
        );
        expect(apkOnly.downloadUrlForPlatform('linux'), isEmpty);
      },
    );

    test(
      'Android usa apkDownloadUrl y nunca cae a un paquete de escritorio',
      () {
        expect(
          fullRelease.downloadUrlForPlatform('android'),
          'https://example.test/app-arm64-v8a-release.apk',
        );
        final desktopOnly = InutilReleaseInfo(
          currentVersion: '2.5.14',
          latestVersion: '2.5.15',
          releaseNotes: const ['Solo escritorio.'],
          windowsDownloadUrl: 'https://example.test/setup.exe',
          linuxDownloadUrl: 'https://example.test/linux.tar.gz',
          publishedAt: DateTime.utc(2026, 11, 21),
        );
        expect(desktopOnly.downloadUrlForPlatform('android'), isEmpty);
      },
    );

    test('Plataformas sin instalador OTA directo (iOS) nunca caen al APK', () {
      expect(fullRelease.downloadUrlForPlatform('ios'), isEmpty);
    });

    test('downloadUrlForAbi en escritorio no devuelve el APK de Android', () {
      // En entorno de pruebas Linux/macOS/Windows, Platform.isAndroid es false.
      expect(
        fullRelease.downloadUrlForAbi('arm64-v8a'),
        fullRelease.platformDownloadUrl,
      );
      expect(
        fullRelease.downloadUrlForAbi('arm64-v8a'),
        isNot(contains('.apk')),
      );
    });

    test('toJson y fromJson preservan URLs de escritorio y checksums', () {
      final roundTrip = InutilReleaseInfo.fromJson(fullRelease.toJson());
      expect(roundTrip.windowsDownloadUrl, fullRelease.windowsDownloadUrl);
      expect(roundTrip.macosDownloadUrl, fullRelease.macosDownloadUrl);
      expect(
        roundTrip.macosArm64DownloadUrl,
        fullRelease.macosArm64DownloadUrl,
      );
      expect(roundTrip.macosX64DownloadUrl, fullRelease.macosX64DownloadUrl);
      expect(roundTrip.linuxDebDownloadUrl, fullRelease.linuxDebDownloadUrl);
      expect(roundTrip.linuxRpmDownloadUrl, fullRelease.linuxRpmDownloadUrl);
      expect(roundTrip.checksums, fullRelease.checksums);
    });

    test('extensionForDownloadUrl deduce la extensión real del instalador', () {
      expect(
        InutilReleaseInfo.extensionForDownloadUrl(
          'https://example.test/InutilMusic-2.5.15-Windows-x64-Setup.exe',
          operatingSystem: 'windows',
        ),
        '.exe',
      );
      expect(
        InutilReleaseInfo.extensionForDownloadUrl(
          'https://example.test/InutilMusic-2.5.15-macOS-arm64.pkg',
          operatingSystem: 'macos',
        ),
        '.pkg',
      );
      expect(
        InutilReleaseInfo.extensionForDownloadUrl(
          'https://example.test/InutilMusic-2.5.15-linux-amd64.deb',
          operatingSystem: 'linux',
        ),
        '.deb',
      );
      expect(
        InutilReleaseInfo.extensionForDownloadUrl(
          'https://example.test/InutilMusic-2.5.15-linux-x86_64.rpm',
          operatingSystem: 'linux',
        ),
        '.rpm',
      );
      expect(
        InutilReleaseInfo.extensionForDownloadUrl(
          'https://example.test/inutil_music_linux_x64.tar.gz',
          operatingSystem: 'linux',
        ),
        '.tar.gz',
      );
      expect(
        InutilReleaseInfo.extensionForDownloadUrl(
          'https://example.test/Inutil.Music-Linux-x86_64.AppImage',
          operatingSystem: 'linux',
        ),
        '.AppImage',
      );
      expect(
        InutilReleaseInfo.extensionForDownloadUrl(
          'https://example.test/app-arm64-v8a-release.apk?alt=media',
          operatingSystem: 'android',
        ),
        '.apk',
      );
    });
  });
}

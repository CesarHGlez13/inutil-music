import 'dart:convert';
import 'dart:io';

import 'package:inutil_music/core/constants/app_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release metadata exposes the same version and build number', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final readme = File('README.md').readAsStringSync();
    final changelog = File('CHANGELOG.md').readAsStringSync();
    final windowsInstaller = File(
      'packaging/windows/InutilMusic.iss',
    ).readAsStringSync();
    final pubspecVersion = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec)?.group(1);
    final readmeVersion = RegExp(
      r'Current version:\s*\*\*([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)\*\*',
    ).firstMatch(readme)?.group(1);
    final changelogVersion = RegExp(
      r'^##\s+([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)\s+',
      multiLine: true,
    ).firstMatch(changelog)?.group(1);
    final runtimeVersion = pubspecVersion?.split('+').first;
    final installerVersion = RegExp(
      r'#define MyAppVersion "([0-9]+\.[0-9]+\.[0-9]+)"',
    ).firstMatch(windowsInstaller)?.group(1);

    expect(pubspecVersion, '2.5.13+4271');
    expect(readmeVersion, pubspecVersion);
    expect(changelogVersion, pubspecVersion);
    expect(runtimeVersion, AppConstants.appVersion);
    expect(installerVersion, AppConstants.appVersion);
    expect(windowsInstaller, contains('AppVersion={#MyAppVersion}'));
    expect(
      windowsInstaller,
      contains('AppVerName={#MyAppName} {#MyAppVersion}'),
    );
  });

  test('uses the requested search size and official project URLs', () {
    expect(AppConstants.defaultSearchLimit, 20);
    expect(
      AppConstants.githubRepositoryUrl,
      'https://github.com/CesarHGlez13/inutil-music',
    );
    expect(
      AppConstants.appDownloadUrl,
      'https://github.com/CesarHGlez13/inutil-music/releases/latest',
    );
    // El contacto visible es el correo propio del proyecto; la cuenta de
    // administrador de Firebase vive aparte en `bootstrapAdminEmail`.
    expect(AppConstants.supportEmail, 'cesarmaster133@gmail.com');
    // «Apoyar el desarrollo» ya no apunta al Ko-fi del autor original: escribe a
    // el correo propio mediante `mailto:`.
    expect(
      AppConstants.supportDevelopmentUrl,
      startsWith('mailto:${AppConstants.supportEmail}'),
    );
    expect(AppConstants.supportDevelopmentUrl, isNot(contains('ko-fi')));
  });

  test('brand strings point at Inútil Music, not the upstream project', () {
    final constants = File('lib/core/constants/app_constants.dart')
        .readAsStringSync();
    final settingsPanel = File(
      'lib/features/music/presentation/widgets/settings_panel.dart',
    ).readAsStringSync();
    final widgetEs = File(
      'android/app/src/main/res/values/widget_strings.xml',
    ).readAsStringSync();
    final widgetEn = File(
      'android/app/src/main/res/values-en/widget_strings.xml',
    ).readAsStringSync();

    expect(AppConstants.appName, 'Inútil Music');
    // Ninguna URL del repositorio, las descargas o el contacto debe apuntar ya
    // al proyecto original.
    for (final stale in <String>[
      'BryamContreras/BStream-Music',
      'bstreammusic.pages.dev',
      'BStream',
    ]) {
      expect(constants, isNot(contains(stale)), reason: '$stale must be gone');
    }
    // El pie de Ajustes muestra unicamente la marca y soporte propios.
    expect(settingsPanel, contains("'Inútil Music v\${AppConstants.appVersion} · '"));
    expect(settingsPanel, contains('AppConstants.supportEmail'));
    // El nombre del widget visible en el launcher debe ser el nuestro.
    for (final xml in <String>[widgetEs, widgetEn]) {
      expect(xml, isNot(contains('BStream Music')));
      expect(xml, contains('Inútil Music'));
    }
    // Sin mojibake en las cadenas en español.
    expect(widgetEs, isNot(contains('canciÃ³n')));
  });

  test(
    'el producto no contiene ninguna referencia interna o externa a bstream',
    () {
      final roots = <String>[
        'lib',
        'android/app/src',
        'ios/Runner',
        'ios/NowPlayingWidget',
        'macos/Runner',
        'windows/runner',
        'linux/runner',
        'packaging',
        'integration_test',
      ];
      final unexpected = <String>[];
      for (final root in roots) {
        for (final entry in Directory(root).listSync(recursive: true, followLinks: false)) {
          if (entry is! File) continue;
          final path = entry.path;
          if (!path.endsWith('.dart') &&
              !path.endsWith('.kt') &&
              !path.endsWith('.java') &&
              !path.endsWith('.swift') &&
              !path.endsWith('.cc') &&
              !path.endsWith('.cpp') &&
              !path.endsWith('.rc') &&
              !path.endsWith('.xml') &&
              !path.endsWith('.plist') &&
              !path.endsWith('.entitlements') &&
              !path.endsWith('.xcconfig') &&
              !path.endsWith('.iss') &&
              !path.endsWith('.spec') &&
              !path.endsWith('.desktop') &&
              !path.endsWith('.sh') &&
              !path.endsWith('.txt')) {
            continue;
          }
          final lines = entry.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            if (!lines[i].toLowerCase().contains('bstream')) continue;
            unexpected.add('$path:${i + 1}  ${lines[i].trim()}');
          }
        }
      }
      expect(unexpected, isEmpty, reason: 'referencias residuales: $unexpected');

      final pubspec = File('pubspec.yaml').readAsStringSync();
      final license = File('LICENSE').readAsStringSync();
      final notices = File('THIRD_PARTY_NOTICES.md').readAsStringSync();
      final settingsPanel = File(
        'lib/features/music/presentation/widgets/settings_panel.dart',
      ).readAsStringSync();
      expect(pubspec, contains('- LICENSE'));
      expect(pubspec, contains('- THIRD_PARTY_NOTICES.md'));
      expect(license, contains('Copyright (c) 2026, Bryam Contreras'));
      expect(notices, contains('Copyright (c) 2026, Bryam Contreras'));
      expect(license.toLowerCase(), isNot(contains('bstream')));
      expect(notices.toLowerCase(), isNot(contains('bstream')));
      expect(settingsPanel, contains("ValueKey('settings-about-licenses')"));
      expect(settingsPanel, contains("rootBundle.loadString('THIRD_PARTY_NOTICES.md')"));
      expect(settingsPanel, contains('showLicensePage('));
    },
  );

  test('uses only the in-process Dart YouTube resolver architecture', () {
    final pubspec = File('pubspec.yaml').readAsStringSync().toLowerCase();
    final lockfile = File('pubspec.lock').readAsStringSync().toLowerCase();
    final nightlyWorkflow = File(
      '.github/workflows/nightly-smoke.yml',
    ).readAsStringSync();

    expect(pubspec, isNot(contains('youtube_explode_dart')));
    expect(lockfile, isNot(contains('youtube_explode_dart')));
    expect(pubspec, isNot(contains('yt-dlp')));
    expect(lockfile, isNot(contains('yt-dlp')));
    expect(
      nightlyWorkflow,
      contains('integration_test/innertube_playback_live_test.dart'),
    );
    expect(
      nightlyWorkflow,
      contains('--dart-define=INUTIL_LIVE_INNERTUBE=true'),
    );
    expect(
      nightlyWorkflow,
      isNot(contains('youtube_explode_playback_test.dart')),
    );
  });

  test('Android emulator runner receives complete single-line commands', () {
    final workflow = File(
      '.github/workflows/nightly-smoke.yml',
    ).readAsStringSync();
    // android-emulator-runner executes each script line in its own shell;
    // backslash continuations would invoke flutter with a target named "\\".
    final commands = const LineSplitter()
        .convert(workflow)
        .skipWhile((line) => line.trim() != 'script: |')
        .skip(1)
        .takeWhile((line) => line.startsWith('            ') || line.isEmpty)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    expect(commands, hasLength(2));
    for (final (index, target) in [
      'crossfade_native_test.dart',
      'skip_silence_native_test.dart',
    ].indexed) {
      expect(
        commands[index],
        'flutter drive --driver=test_driver/integration_test.dart '
        '--target=integration_test/$target -d emulator-5554 --no-dds',
      );
    }
  });

  test('release packaging is hermetic and declares Linux secure storage', () {
    final workflow = File(
      '.github/workflows/desktop-builds.yml',
    ).readAsStringSync();
    final linuxPackages = File(
      'packaging/linux/build_packages.sh',
    ).readAsStringSync();
    final rpmSpec = File(
      'packaging/linux/inutil-music.spec',
    ).readAsStringSync();
    final attributes = File('.gitattributes').readAsStringSync();

    expect(workflow, contains('Dir::Etc::sourcelist=/etc/apt/sources.list'));
    expect(workflow, contains('inutil-apt-sourceparts'));
    expect(workflow, contains('Dir::Etc::sourceparts=\$apt_sourceparts'));
    expect(workflow, contains('Acquire::Retries=5'));
    expect(workflow, contains('libsecret-1-dev'));
    expect(workflow, contains('Verify Linux installer payloads'));
    expect(workflow, contains('test -x "\$bundle/Inútil Music"'));
    expect(workflow, contains('dpkg-deb --extract'));
    expect(workflow, contains('rpm2cpio'));
    expect(linuxPackages, contains('libsecret-1-0'));
    expect(rpmSpec, contains('Requires:       libsecret'));
    expect(attributes, contains('packaging/linux/inutil-music text eol=lf'));

    for (final legacyDirectory in <String>[
      'third_party/youtube_explode_dart',
      'lib/services/downloader/adapters/youtube_explode',
      'windows/tools',
      'linux/tools',
      'macos/tools',
    ]) {
      expect(
        Directory(legacyDirectory).existsSync(),
        isFalse,
        reason: '$legacyDirectory must not remain as an empty placeholder',
      );
    }
  });
}

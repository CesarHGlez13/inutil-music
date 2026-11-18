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
      'packaging/windows/BStreamMusic.iss',
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

    expect(pubspecVersion, '2.1.0+210');
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
    // El contacto propio coincide con el fundador de las reglas de Firestore.
    expect(AppConstants.supportEmail, 'cesar@inutilmusic.com');
    // El único resto del proyecto original en estas constantes es el credito
    // legal que exige la licencia BSD-2-Clause del upstream.
    expect(AppConstants.upstreamCredit, contains('BSD-2-Clause'));
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
    ]) {
      expect(constants, isNot(contains(stale)), reason: '$stale must be gone');
    }
    // El pie de Ajustes muestra la marca propia y conserva el credito legal.
    expect(settingsPanel, contains("'Inútil Music v\${AppConstants.appVersion} · '"));
    expect(settingsPanel, contains('AppConstants.upstreamCredit'));
    expect(settingsPanel, contains('AppConstants.supportEmail'));
    // El nombre del widget visible en el launcher debe ser el nuestro.
    for (final xml in <String>[widgetEs, widgetEn]) {
      expect(xml, isNot(contains('BStream Music')));
      expect(xml, contains('Inútil Music'));
    }
    // Sin mojibake en las cadenas en español.
    expect(widgetEs, isNot(contains('canciÃ³n')));
  });

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
      contains('--dart-define=BSTREAM_LIVE_INNERTUBE=true'),
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
      'packaging/linux/bstream-music.spec',
    ).readAsStringSync();
    final attributes = File('.gitattributes').readAsStringSync();

    expect(workflow, contains('Dir::Etc::sourcelist=/etc/apt/sources.list'));
    expect(workflow, contains('bstream-apt-sourceparts'));
    expect(workflow, contains('Dir::Etc::sourceparts=\$apt_sourceparts'));
    expect(workflow, contains('Acquire::Retries=5'));
    expect(workflow, contains('libsecret-1-dev'));
    expect(workflow, contains('Verify Linux installer payloads'));
    expect(workflow, contains('test -x "\$bundle/BStream Music"'));
    expect(workflow, contains('dpkg-deb --extract'));
    expect(workflow, contains('rpm2cpio'));
    expect(linuxPackages, contains('libsecret-1-0'));
    expect(rpmSpec, contains('Requires:       libsecret'));
    expect(attributes, contains('packaging/linux/bstream-music text eol=lf'));

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

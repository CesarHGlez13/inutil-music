class AppConstants {
  const AppConstants._();

  static const appName = 'Inútil Music';
  /// Fuente única del número de versión mostrado en Ajustes y usado por el
  /// chequeo de actualizaciones OTA. Debe coincidir con la parte de versión de
  /// `version:` en `pubspec.yaml` (actualmente `2.1.0+210`); el incremento
  /// interno (`+210`) es el `versionCode` de Android y no se muestra.
  static const appVersion = '2.1.0';
  static const databaseName = 'inutil_music.db';
  static const databaseVersion = 11;
  static const fileExportChannel = 'inutil_music/file_export';
  static const androidFileExportChannel = fileExportChannel;
  static const androidScreenChannel = 'inutil_music/screen';
  static const androidSupportedLinksSettingsChannel =
      'inutil_music/supported_links_settings';
  static const androidExternalAudioChannel = 'inutil_music/external_audio';
  static const androidAppActivationChannel = 'inutil_music/app_activation';
  static const defaultSearchLimit = 20;
  static const supportDevelopmentUrl = 'https://ko-fi.com/soybryam06c/donate';
  /// Repositorio propio de Inútil Music (artefactos publicados y notas de
  /// versión). Es la fuente del manifiesto OTA `release.json`; ver §10 del
  /// informe y `docs/RELEASES.md`.
  static const githubRepositoryUrl =
      'https://github.com/CesarHGlez13/inutil-music';
  /// Página de descargas: la última Release publicada del repositorio propio,
  /// la misma que resuelve `checkForUpdate()`.
  static const appDownloadUrl =
      'https://github.com/CesarHGlez13/inutil-music/releases/latest';
  /// Contacto del proyecto (fundador, también `bootstrapAdminEmail` en
  /// `firebase_auth_service.dart` y en las reglas de Firestore/Storage).
  static const supportEmail = 'cesar@inutilmusic.com';
  /// Crédito legal obligatorio: el proyecto parte de BStream Music, publicado
  /// bajo BSD-2-Clause (ver `LICENSE`).
  static const upstreamCredit =
      'basado en el proyecto open-source BStream Music (BSD-2-Clause)';
}

class AppConstants {
  const AppConstants._();

  static const appName = 'Inútil Music';
  /// Fuente única del número de versión mostrado en Ajustes y usado por el
  /// chequeo de actualizaciones OTA. Debe coincidir con la parte de versión de
  /// `version:` en `pubspec.yaml` (actualmente `2.1.2+212`); el incremento
  /// interno (`+212`) es el `versionCode` de Android y no se muestra.
  static const appVersion = '2.1.2';
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
  /// «Apoyar el desarrollo» abre el cliente de correo del dispositivo
  /// escribiendo a `supportEmail` (asunto prellenado); todavía no hay medio de
  /// pago propio enlazado. Se usa `mailto:` en lugar de una URL web porque el
  /// lanzador de Ajustes es `launchUrl(..., externalApplication)`, que resuelve
  /// ese esquema en Android, Linux y Windows.
  static const supportDevelopmentUrl =
      'mailto:cesarmaster133@gmail.com'
      '?subject=In%C3%BAtil%20Music%20-%20apoyo%20al%20desarrollo';
  /// Repositorio propio de Inútil Music (artefactos publicados y notas de
  /// versión). Es la fuente del manifiesto OTA `release.json`; ver §10 del
  /// informe y `docs/RELEASES.md`.
  static const githubRepositoryUrl =
      'https://github.com/CesarHGlez13/inutil-music';
  /// Página de descargas: la última Release publicada del repositorio propio,
  /// la misma que resuelve `checkForUpdate()`.
  static const appDownloadUrl =
      'https://github.com/CesarHGlez13/inutil-music/releases/latest';
  /// Contacto visible del proyecto (pie de la pantalla «Acerca de»).  La
  /// cuenta de administrador de Firebase sigue en
  /// `bootstrapAdminEmail` (`firebase_auth_service.dart`) porque está ligada al
  /// usuario de Firebase Auth ya registrado y a las reglas de Firestore.
  static const supportEmail = 'cesarmaster133@gmail.com';
  /// Crédito legal obligatorio: el proyecto parte de BStream Music, publicado
  /// bajo BSD-2-Clause (ver `LICENSE`).
  static const upstreamCredit =
      'basado en el proyecto open-source BStream Music (BSD-2-Clause)';
}

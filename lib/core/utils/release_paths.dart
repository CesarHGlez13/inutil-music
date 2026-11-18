import 'dart:io';

import 'package:path/path.dart' as p;

/// Rutas compartidas del canal de actualizaciones local.
///
/// Inútil Music puede servir sus propias versiones desde una carpeta del
/// equipo (sin depender de la nube): el PC descubre el manifiesto
/// `release.json`, lo publica por HTTP en `/api/release` y sirve los
/// artefactos `.apk` / `.tar.gz` que Cesar deposite en esa carpeta.
///
/// Ubicación por defecto: `~/inutil-releases/` (anulable con la variable de
/// entorno `INUTIL_RELEASES_DIR`).
class InutilReleasePaths {
  InutilReleasePaths._();

  static const String manifestName = 'release.json';

  static Directory dir() {
    final override = (Platform.environment['INUTIL_RELEASES_DIR'] ?? '').trim();
    if (override.isNotEmpty) return Directory(override);
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return Directory(p.join(home, 'inutil-releases'));
  }

  static File manifestFile() => File(p.join(dir().path, manifestName));

  /// Artefacto dentro de la carpeta de versiones, o `null` si el nombre
  /// intentaba salirse del directorio (protección contra path traversal).
  static File? artifact(String name) {
    final clean = name.trim();
    if (clean.isEmpty ||
        clean == '.' ||
        clean == '..' ||
        clean.contains('/') ||
        clean.contains(r'\')) {
      return null;
    }
    return File(p.join(dir().path, clean));
  }
}

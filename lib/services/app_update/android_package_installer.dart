import 'dart:io';

import 'package:flutter/services.dart';

/// Puente con el `MethodChannel` nativo `inutil_music/app_update`.
///
/// La instalación real la hace Android: `MainActivity.installDownloadedPackage`
/// expone el APK con `androidx.core.content.FileProvider` (URI `content://`) y
/// lanza `Intent.ACTION_VIEW` con el MIME `application/vnd.android.package-archive`.
/// Desde API 24 una URI `file://` que sale de la aplicación lanza
/// `FileUriExposedException`, por eso el APK debe pasar por el FileProvider
/// declarado en `AndroidManifest.xml` con `res/xml/provider_paths.xml`.
///
/// Cesar acepta el instalador manualmente: la app nunca invoca una instalación
/// silenciosa ni pide permisos de root.
class AndroidPackageInstaller {
  const AndroidPackageInstaller._();

  static const MethodChannel channel = MethodChannel('inutil_music/app_update');

  static bool get isSupported => Platform.isAndroid;

  /// ABI principal del dispositivo, usada para elegir el APK dividido
  /// (`arm64-v8a`, `armeabi-v7a`, `x86_64`, …) publicado en Firestore.
  static Future<String> primaryAbi() async {
    if (!isSupported) return '';
    try {
      final abi = await channel.invokeMethod<String>('primaryAbi');
      return (abi ?? '').trim();
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }

  /// Lista ordenada de ABIs soportadas por el dispositivo (`Build.SUPPORTED_ABIS`).
  /// Garantiza elegir siempre una ABI compatible (por ejemplo `armeabi-v7a` en
  /// teléfonos Motorola 32-bit o `arm64-v8a` en equipos 64-bit-only).
  static Future<List<String>> supportedAbis() async {
    if (!isSupported) return const <String>[];
    try {
      final raw = await channel.invokeMethod<List<Object?>>('supportedAbis');
      if (raw != null && raw.isNotEmpty) {
        return raw
            .map((item) => (item?.toString() ?? '').trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
    } on PlatformException {
      // Cae a primaryAbi().
    } on MissingPluginException {
      // Cae a primaryAbi().
    }
    final primary = await primaryAbi();
    return primary.isEmpty ? const <String>[] : <String>[primary];
  }

  /// `true` cuando Android ya permite instalar apps de orígenes desconocidos.
  /// Antes de API 26 siempre devuelve `true`.
  static Future<bool> canRequestPackageInstalls() async {
    if (!isSupported) return true;
    try {
      final allowed = await channel.invokeMethod<bool>(
        'canRequestPackageInstalls',
      );
      return allowed ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return true;
    }
  }

  /// Abre el ajuste de Android «instalar aplicaciones desconocidas».
  static Future<bool> openInstallUnknownAppsSettings() async {
    if (!isSupported) return false;
    try {
      final opened = await channel.invokeMethod<bool>(
        'openInstallUnknownAppsSettings',
      );
      return opened ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Verifica exhaustivamente la compatibilidad del APK descargado contra este
  /// dispositivo (compatibilidad de arquitectura ABI, coincidencia de firma y
  /// relación de versiones) antes de pasarlo al instalador de Android.
  static Future<Map<String, dynamic>?> verifyPackage(String apkPath) async {
    if (!isSupported) return null;
    try {
      final res = await channel.invokeMapMethod<String, dynamic>(
        'verifyPackage',
        <String, Object?>{'path': apkPath},
      );
      return res;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Entrega [apkPath] al instalador de paquetes. Devuelve `null` cuando el
  /// instalador se abrió; en caso contrario, un mensaje en español listo para
  /// mostrar en la interfaz.
  static Future<String?> installPackage(String apkPath) async {
    if (!isSupported) {
      return 'La instalación automática sólo está disponible en Android.';
    }
    try {
      final opened = await channel.invokeMethod<bool>(
        'installPackage',
        <String, Object?>{'path': apkPath},
      );
      if (opened == true) return null;
      return 'El instalador de Android no respondió.';
    } on PlatformException catch (error) {
      final message = error.message;
      return message == null || message.isEmpty
          ? 'No se pudo abrir el instalador de Android.'
          : message;
    } on MissingPluginException {
      return 'El instalador nativo no está disponible en esta compilación.';
    }
  }
}

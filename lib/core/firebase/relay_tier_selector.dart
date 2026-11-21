/// Selector de tier de datos para INÚTIL MUSIC.
///
/// Tres tiers, en este orden estricto:
///
/// 1. `lanRelay`  — el S7 Edge (`inutil_relay/relay.py`) en `http://host:puerto`.
///    Cero lecturas pagadas de la cuota de Firestore, pero sólo vive dentro de
///    la LAN de la casa (medido: `cache_hits 1518` vs `revalidations 118` =
///    92.7 % servido del cache, `writes_client 197` vs `writes_upstream 26` =
///    13.2 % de escrituras pagadas).
/// 2. `cloudRelay` — el Worker `inutil_cloud_relay` en `https://<host>`.
///    Mismo contrato REST, alcanzable desde CUALQUIER red. Cierra el hueco de
///    los builds horneados con `FB_RELAY_HOST` fuera de la LAN, que hoy pagan
///    la cuota entera contra Google.
/// 3. `google`     — `firestore.googleapis.com`. Paga cuota, siempre funciona.
///
/// Todo aquí es **puro**: no toca la red, no lee `SharedPreferences`, no tiene
/// estado de clase. Las sondas de alcance viven en `FirebaseConfig` y le pasan
/// el resultado como parámetro. Así el árbol de decisión se puede probar
/// entero sin levantar servidores.
library;

import 'package:flutter/foundation.dart';

/// Qué endpoint de datos va a usar la app en este instante.
enum RelayTier { lanRelay, cloudRelay, google }

/// Parámetros de la decisión. `[lanReachable]` es `bool?` porque el estado de
/// la sonda arranca `null` (= todavía sin medir) y eso NO es lo mismo que
/// `false`: con `null` un build horneado con `FB_RELAY_HOST` todavía no sabe
/// si está en casa, y comportarse como `false` mandaría a un usuario en casa a
/// pagar cuota durante los primeros segundos de cada sesión.
@immutable
class RelayTierInputs {
  const RelayTierInputs({
    required this.lanHost,
    required this.lanPort,
    required this.emulator,
    required this.lanReachable,
    required this.cloudHost,
    this.cloudScheme = 'https',
    this.cloudPort = '',
  });

  /// Host del relay LAN (el S7). Vacío = build sin relay horneado.
  final String lanHost;

  /// Puerto del relay LAN.
  final String lanPort;

  /// true cuando se usa la suite de emuladores: el emulador gana sobre
  /// cualquier relay, nunca se le manda tráfico de emulador al S7 ni al cloud.
  final bool emulator;

  /// Medición de la sonda TCP al relay LAN: `null` = sin medir, `true` = vivo,
  /// `false` = no respondió.
  final bool? lanReachable;

  /// Host del Worker cloud (p. ej.
  /// `inutil-cloud-relay.scada-xiaomi-server.workers.dev`). Vacío = build sin
  /// capa cloud.
  final String cloudHost;

  /// Esquema del endpoint cloud. `https` por defecto porque el Worker vive en
  /// `workers.dev` con TLS; se puede bajar a `http` solo para `wrangler dev`
  /// en local.
  final String cloudScheme;

  /// Puerto cloud. Vacío = usar el puerto por defecto del esquema (443 en
  /// https), o sea NO se escribe `:puerto` en la URL. Un `https://host:443`
  /// explícito funciona pero ensucia y rompe comparaciones de string.
  final String cloudPort;
}

/// Constructor de URLs de tier, puro.
class RelayTierSelector {
  const RelayTierSelector._();

  /// Ruta de documentos de Firestore, idéntica a la de Google: `relay.py` y el
  /// Worker hablan el mismo dialecto REST y cualquier diferencia de ruta les
  /// devolvería 404.
  static const String documentsPathSuffix =
      '/v1/projects/%PROJECT%/databases/(default)/documents';

  /// Ruta de objetos de Cloud Storage, también idéntica a la de Google.
  static const String storagePathSuffix = '/v0/b/%BUCKET%/o';

  /// Decisión pura. Reglas, en orden:
  ///
  /// * emulador → `google` (el llamante decide el endpoint del emulador;
  ///   ningún relay recibe tráfico de emulador);
  /// * relay LAN configurado, fuera de emuladores y declarado **vivo** →
  ///   `lanRelay`;
  /// * si no, capa cloud configurada y fuera de emuladores → `cloudRelay`;
  /// * si no → `google`.
  ///
  /// Nota: `null` en `[lanReachable]` cuenta como "no usar LAN", igual que
  /// `false`, pero sólo para esta decisión de TIER; `FirebaseConfig` conserva
  /// su semántica de `null` para no penalizar a quien sí está en casa.
  static RelayTier select(RelayTierInputs i) {
    if (i.emulator) return RelayTier.google;
    if (i.lanHost.trim().isNotEmpty && i.lanReachable == true) {
      return RelayTier.lanRelay;
    }
    if (i.cloudHost.trim().isNotEmpty) return RelayTier.cloudRelay;
    return RelayTier.google;
  }

  /// URL de tier a partir de una URL de referencia de Google (de la que se
  /// copia la RUTA exacta) y/o una del emulador.
  ///
  /// `[emulatorUrl]` se devuelve tal cual cuando `[i.emulator]` es true, para
  /// no cambiar el comportamiento actual de `FirebaseConfig`.
  static String urlFor({
    required RelayTierInputs i,
    required String googleUrl,
    String? emulatorUrl,
    String projectId = '',
    String storageBucket = '',
  }) {
    final tier = select(i);
    if (i.emulator) return emulatorUrl ?? googleUrl;
    if (tier == RelayTier.lanRelay) {
      return 'http://${i.lanHost.trim()}:${_port(i.lanPort)}'
          '${_path(googleUrl, projectId, storageBucket)}';
    }
    if (tier == RelayTier.cloudRelay) {
      return cloudUrl(i, googleUrl, projectId, storageBucket);
    }
    return googleUrl;
  }

  /// URL del tier cloud. `https` sin `:puerto` cuando `[i.cloudPort]` está
  /// vacío; con puerto explícito solo si el llamante lo pidió.
  static String cloudUrl(
    RelayTierInputs i,
    String googleUrl,
    String projectId,
    String storageBucket,
  ) {
    final host = i.cloudHost.trim();
    final scheme = _scheme(i.cloudScheme);
    final port = i.cloudPort.trim();
    final authority = port.isEmpty ? host : '$host:$port';
    return '$scheme://$authority'
        '${_path(googleUrl, projectId, storageBucket)}';
  }

  /// true solo para `https`: un `cloudScheme` inventado no puede colar
  /// cualquier texto dentro de la URL.
  static String _scheme(String raw) =>
      raw.trim().toLowerCase() == 'http' ? 'http' : 'https';

  /// Puerto LAN: fallback conservador a 8080 si el horneado no parsea.
  static String _port(String raw) => raw.trim().isEmpty ? '8080' : raw.trim();

  /// Ruta de la URL de referencia, con `%PROJECT%`/`%BUCKET%` sustituidos si
  /// el llamante los pasa. Si la referencia ya trae su ruta, se usa tal cual.
  static String _path(
    String googleUrl,
    String projectId,
    String storageBucket,
  ) {
    final p = Uri.parse(googleUrl).path;
    if (p.isNotEmpty) return p;
    if (projectId.isNotEmpty) {
      return documentsPathSuffix.replaceAll('%PROJECT%', projectId);
    }
    if (storageBucket.isNotEmpty) {
      return storagePathSuffix.replaceAll('%BUCKET%', storageBucket);
    }
    return '';
  }
}

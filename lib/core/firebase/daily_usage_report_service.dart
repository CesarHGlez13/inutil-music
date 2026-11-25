/// Reporte diario de telemetría de INUTIX MUSIC hacia el relay.
///
/// Contrato ya en producción y verificado (commit `8eddb17` de `inutil_relay`),
/// NO lo cambies:
///   `POST {BASE}/metrics/<uid>/daily`, donde `{BASE}` es el prefijo REST de
///   Firestore que la app YA usa (`.../databases/(default)/documents`).
///
/// El cuerpo es JSON plano con las claves de esta app (`musicMinutes`,
/// `musicPlays`, `musicOpens`, `musicPlaylists`, `musicFavorites` y
/// `source: "music"`), todas opcionales, y `day` en `YYYYMMDD`. Es el TOTAL
/// ACUMULADO del día calendario UTC, no un delta: el relay hace merge por
/// columna (el último valor del día gana), así que reenviar el mismo total es
/// idempotente y seguro.
///
/// Máximo 1 escritura por día por app. Se dispara en el momento de cierre que
/// ya existe — el `pushNow()` del respaldo en la nube, que `main.dart` llama al
/// pausar o salir — y nada más. No hay timers nuevos ni polls: el reintento
/// offline es el de la propia app, en el siguiente momento de cierre.
///
/// Todo lo decisivo es inyectable para poder probarlo sin levantar red.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/music/domain/entities/playlist.dart';
import '../../services/storage/local_database_service.dart';
import 'firebase_auth_service.dart';
import 'firebase_config.dart';
import 'firebase_firestore_service.dart';
import 'inutil_wrapped_service.dart';
import 'relay_tier_selector.dart';

/// Transporte HTTP inyectable: manda el JSON plano a la ruta del contrato
/// (`metrics/<uid>/daily`) y devuelve la respuesta. En producción es el cliente
/// REST de Firestore con su fallback de relay intacto; en las pruebas es un fake
/// sin red.
typedef DailyReportTransport =
    Future<http.Response> Function(String path, String jsonBody);

/// Contadores inyectables, leídos de la fuente real de cada número.
typedef DailyReportIntGetter = Future<int> Function();

/// Decisiones inyectables (gate de sesión).
typedef DailyReportBoolGetter = bool Function();

/// Lectura de los totales acumulados del día en el store de estadísticas.
typedef DailyReportDayTotals = Future<WrappedDayTotals> Function(String dayKey);

/// Tier de datos y host del endpoint resuelto, leídos del selector de tier.
typedef DailyReportTierGetter = RelayTier Function();
typedef DailyReportHostGetter = String Function();

/// Reloj inyectable para el día calendario UTC.
typedef DailyReportClock = DateTime Function();

/// Dependencias del reporte, todas opcionales: sin ellas usa las fuentes reales
/// de la app (`FirebaseConfig`, `InutilFirestoreService`,
/// `InutilWrappedService`, `InutilAuthService`). Las pruebas inyectan un fake
/// del layer HTTP, un uid sintáctico y un reloj fijo, así que ningún paso toca
/// la red ni la producción.
@immutable
class DailyUsageReportHooks {
  const DailyUsageReportHooks({
    this.currentUid,
    this.canSync,
    this.dataTier,
    this.endpointHost,
    this.dayTotals,
    this.playlistsCount,
    this.favoritesCount,
    this.transport,
    this.clock,
  });

  /// `null` = sin sesión iniciada: el reporte no se manda.
  final String? Function()? currentUid;

  /// Mismo gate que el resto de la app: autenticado, vigente y con token.
  final DailyReportBoolGetter? canSync;

  /// Tier de datos efectivo ahora mismo y host del endpoint resuelto.
  final DailyReportTierGetter? dataTier;
  final DailyReportHostGetter? endpointHost;

  /// Totales acumulados del día calendario UTC, leídos del mismo store que
  /// alimenta el Wrapped (`InutilWrappedService`).
  final DailyReportDayTotals? dayTotals;

  /// Playlists y favoritos del usuario, leídos de la base local.
  final DailyReportIntGetter? playlistsCount;
  final DailyReportIntGetter? favoritesCount;

  /// Capa HTTP.
  final DailyReportTransport? transport;

  /// Reloj del día calendario UTC.
  final DailyReportClock? clock;
}

/// Reporte diario de uso de INUTIX MUSIC: una sola escritura al día, disparada
/// en el momento de cierre que ya existe.
///
/// El marker de «ya reportado hoy» se persiste en `SharedPreferences` porque el
/// límite es una escritura por DÍA, no por sesión de la app. Si la escritura
/// falla por red, el día queda pendiente y se reintenta en el siguiente momento
/// de cierre con el total acumulado a ese momento — el relay hace merge por
/// columna, así que reenviar es seguro.
class DailyUsageReportService {
  /// `[database]` es la base local: de ella salen los conteos de playlists y
  /// favoritos. `null` = sin fuente, y entonces esos dos números sólo los
  /// aportan las hooks de prueba.
  DailyUsageReportService({this.database, this.hooks});

  final LocalDatabaseService? database;

  @visibleForTesting
  final DailyUsageReportHooks? hooks;

  /// Clave de prefs del último día ya reportado. El valor es `<uid>|YYYYMMDD`
  /// UTC: el límite de una escritura por día es por cuenta, así que cambiar de
  /// cuenta no deja al usuario nuevo sin su reporte.
  static const String reportedDayPrefKey = 'inutil_music_daily_report_day_v1';

  /// Clave de esta app en el contrato del relay.
  static const String source = 'music';

  String? get _uid =>
      hooks?.currentUid?.call() ?? InutilAuthService.instance.currentUser?.uid;

  bool get _canSync =>
      hooks?.canSync?.call() ??
      (InutilAuthService.instance.currentUser?.idToken.isNotEmpty == true &&
          InutilAuthService.instance.isAccessAllowed);

  /// Decisión pura: ¿el endpoint `metrics/<uid>/daily` existe en el destino al
  /// que la app está enrutando HOY?
  ///
  /// Sí en dos casos: el relay LAN del S7 (`relay.py`, que lo implementa) y los
  /// nodos nuestros de `inutix.com` — el S7 tras el túnel de Cloudflare y el
  /// nodo standby — que también son `relay.py`. En el Worker `*.workers.dev`
  /// no: ese nodo sólo conoce `metrics/<uid>/events`. Y en Google tampoco: ahí
  /// el prefijo REST es de documentos y no hay ruta de métricas que responder,
  /// así que por Google el reporte no se manda.
  @visibleForTesting
  static bool dailyRouteAvailable({
    required RelayTier tier,
    required String endpointHost,
  }) {
    final host = endpointHost.trim().toLowerCase();
    if (tier == RelayTier.lanRelay) return true;
    if (tier == RelayTier.cloudRelay || tier == RelayTier.backupRelay) {
      return host.endsWith('.inutix.com');
    }
    return false;
  }

  /// `YYYYMMDD` del día calendario UTC: la misma convención que traen los IDs
  /// de `metrics_daily` del relay.
  @visibleForTesting
  static String dayKeyOf(DateTime moment) {
    final utc = moment.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}$month$day';
  }

  /// Ruta del contrato a partir del uid: `metrics/<uid>/daily`, sobre el
  /// prefijo REST que la app ya usa para escribir en Firestore.
  @visibleForTesting
  static String pathFor(String uid) => 'metrics/$uid/daily';

  /// Cuerpo del reporte: el TOTAL ACUMULADO del día, no un delta. Las claves
  /// son exactamente las de esta app en el contrato y `source` es `music`. Las
  /// minutas se redondean a un decimal, la precisión con la que el relay las
  /// guarda (`ROUND(...,1)`).
  @visibleForTesting
  static Map<String, dynamic> buildBody({
    required String dayKey,
    required double minutes,
    required int plays,
    required int opens,
    required int playlists,
    required int favorites,
  }) {
    return <String, dynamic>{
      'musicMinutes': double.parse(minutes.toStringAsFixed(1)),
      'musicPlays': plays,
      'musicOpens': opens,
      'musicPlaylists': playlists,
      'musicFavorites': favorites,
      'source': source,
      'day': dayKey,
    };
  }

  /// Manda el reporte del día. Devuelve `true` sólo si la escritura llegó; en
  /// ese caso el día queda marcado y ya no se repite hoy.
  ///
  /// Devuelve `false` sin intentar nada cuando: no hay sesión, el día ya está
  /// reportado, el día no tiene ninguna actividad, o el tier de datos no tiene
  /// ruta por el relay (no se inventa una escritura nueva contra Google).
  Future<bool> reportNow() async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return false;
    if (!_canSync) return false;

    final clock = hooks?.clock ?? DateTime.now;
    final dayKey = dayKeyOf(clock());

    final prefs = await SharedPreferences.getInstance();
    final marker = '$uid|$dayKey';
    if (prefs.getString(reportedDayPrefKey) == marker) {
      // Ya se escribió hoy: el límite es una escritura por día.
      return false;
    }

    final tier = hooks?.dataTier?.call() ?? FirebaseConfig.dataTier;
    final host =
        hooks?.endpointHost?.call() ??
        Uri.parse(FirebaseConfig.firestoreBaseUrl).host;
    if (!dailyRouteAvailable(tier: tier, endpointHost: host)) {
      return false;
    }

    final totals = await _dayTotals(dayKey);
    final playlists = await _playlistsCount();
    final favorites = await _favoritesCount();

    // Un día sin ninguna actividad no genera escritura: no hay total nuevo que
    // reportar y el relay ya lo sabe.
    if (totals.minutes <= 0 && totals.plays <= 0 && totals.opens <= 0) {
      return false;
    }

    final body = buildBody(
      dayKey: dayKey,
      minutes: totals.minutes,
      plays: totals.plays,
      opens: totals.opens,
      playlists: playlists,
      favorites: favorites,
    );

    final transport = hooks?.transport ?? _defaultTransport;
    final response = await transport(pathFor(uid), jsonEncode(body));
    if (response.statusCode != 200) {
      // No se marcó el día: el siguiente cierre lo reintenta con el total
      // acumulado a ese momento.
      return false;
    }
    await prefs.setString(reportedDayPrefKey, marker);
    return true;
  }

  /// true si el día ya quedó reportado en este equipo para la cuenta actual: el
  /// llamante puede saber si todavía hay algo pendiente.
  Future<bool> isDayReported(String dayKey) async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(reportedDayPrefKey) == '$uid|$dayKey';
  }

  Future<WrappedDayTotals> _dayTotals(String dayKey) async {
    final hook = hooks?.dayTotals;
    if (hook != null) return hook(dayKey);
    return InutilWrappedService.instance.dayTotals(dayKey);
  }

  Future<int> _playlistsCount() async {
    final hook = hooks?.playlistsCount;
    if (hook != null) return hook();
    if (database == null) return 0;
    final playlists = await database!.getPlaylists();
    return playlists.where((p) => p.deletedAt == null).length;
  }

  Future<int> _favoritesCount() async {
    final hook = hooks?.favoritesCount;
    if (hook != null) return hook();
    if (database == null) return 0;
    final favorites = await database!.getCatalogPlaylist(Playlist.favoritesId);
    return favorites == null ? 0 : favorites.entries.length;
  }

  /// Capa HTTP real: el cliente REST de Firestore con su fallback de relay y
  /// sus headers de siempre. JSON plano, NO la codificación `fields` de
  /// Firestore: es un endpoint propio del relay, no un documento.
  Future<http.Response> _defaultTransport(String path, String jsonBody) =>
      InutilFirestoreService.instance.postJsonToRelay(path, jsonBody);
}

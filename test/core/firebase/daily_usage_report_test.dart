import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:inutil_music/core/firebase/daily_usage_report_service.dart';
import 'package:inutil_music/core/firebase/inutil_wrapped_service.dart';
import 'package:inutil_music/core/firebase/relay_tier_selector.dart';

/// Fake del layer HTTP: apunta la ruta y el cuerpo de cada request y devuelve
/// una respuesta predecible, sin abrir conexión (ningún paso toca la red).
class _FakeTransport {
  _FakeTransport();

  /// Código que la prueba cambia a mano para simular el fallo y el reintento.
  int statusCode = 200;
  final requests = <({String path, Map<String, dynamic> body})>[];

  Future<http.Response> send(String path, String jsonBody) async {
    requests.add((
      path: path,
      body: jsonDecode(jsonBody) as Map<String, dynamic>,
    ));
    return http.Response(
      jsonEncode({'ok': true, 'uid': 'uid_test', 'day': '20261124'}),
      statusCode,
    );
  }
}

/// Prueba del reporte diario de telemetría de INUTIX MUSIC.
///
/// El contrato ya verificado del relay (`8eddb17` de `inutil_relay`) es
/// `POST {BASE}/metrics/<uid>/daily`, con `{BASE}` = el prefijo REST de Firestore
/// que la app YA usa (`.../databases/(default)/documents`). El cuerpo es JSON
/// plano con las claves de esta app (`musicMinutes`, `musicPlays`, `musicOpens`,
/// `musicPlaylists`, `musicFavorites`, `source: "music"`) y `day` en `YYYYMMDD`,
/// y es el TOTAL ACUMULADO del día calendario UTC, no un delta, porque el relay
/// hace merge por columna (el último valor del día gana). Máximo 1 escritura por
/// día por app.
///
/// Las tres cosas que se exigen: (a) la forma exacta del cuerpo, (b) que sea
/// máximo 1 escritura por día y que reenviar el mismo total sea idempotente, (c)
/// que los totales diarios se calculen correctos a partir de los contadores.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// El prefijo REST de Firebase real, el que la app usa cuando no hay relay
  /// horneado. La prueba lo usa como referencia para reconstruir la URL del
  /// contrato tal como la arma el selector de tier.
  const googleBase =
      'https://firestore.googleapis.com/v1/projects/inutil-music-app/databases/(default)/documents';

  late _FakeTransport transport;
  late DailyUsageReportService service;
  final wrapped = InutilWrappedService.instance;

  /// Reloj fijo en UTC: el día calendario que pide el contrato.
  DateTime clockNow = DateTime.utc(2026, 11, 24, 10, 30);

  /// Servicio con las hooks de prueba, apuntando al fake y al reloj fijo.
  DailyUsageReportService buildService({
    String? Function()? currentUid,
    bool Function()? canSync,
    RelayTier Function()? dataTier,
    String Function()? endpointHost,
  }) {
    return DailyUsageReportService(
      hooks: DailyUsageReportHooks(
        currentUid: currentUid ?? (() => 'uid_test'),
        canSync: canSync ?? (() => true),
        // El reporte sale por la ruta que llega al relay: `api.inutix.com` es
        // el S7 Edge tras el túnel de Cloudflare, y `relay.py` es el que
        // implementa el endpoint.
        dataTier: dataTier ?? (() => RelayTier.cloudRelay),
        endpointHost: endpointHost ?? (() => 'api.inutix.com'),
        playlistsCount: () async => 3,
        favoritesCount: () async => 17,
        transport: (path, body) => transport.send(path, body),
        clock: () => clockNow,
      ),
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    transport = _FakeTransport();
    clockNow = DateTime.utc(2026, 11, 24, 10, 30);
    wrapped.resetForTesting();
    wrapped.clockForTesting = () => clockNow;
    service = buildService();
  });

  tearDown(() {
    wrapped.clockForTesting = null;
    wrapped.resetForTesting();
  });

  /// Empuja la posición del reproductor, que es como el store acumula el día.
  void tick(String trackId, int positionMs) {
    wrapped.recordPlaybackTick(
      trackId: trackId,
      title: 'Prueba',
      artist: 'Inutix Music',
      thumbnailUrl: null,
      positionMs: positionMs,
      isPlaying: true,
    );
  }

  group('totales diarios del store (contabilidad en UTC)', () {
    test('minutas, reproducciones y aperturas se cuentan por día', () async {
      tick('t1', 0);
      tick('t1', 10000); // +10 s
      tick('t1', 20000); // +10 s → ya cruza el umbral de reproducción
      tick('t1', 30000); // +10 s
      wrapped.recordAppOpen();

      final totals = await wrapped.dayTotals('20261124');
      expect(totals.dayKey, '20261124');
      expect(totals.minutes, 0.5, reason: '30 s = 0.5 minutas');
      expect(totals.plays, 1, reason: 'una sola reproducción contada');
      expect(totals.opens, 1);
    });

    test('los días se separan: ayer no se mezcla con hoy', () async {
      tick('t1', 0);
      tick('t1', 10000); // +10 s, día 24
      clockNow = DateTime.utc(2026, 11, 25, 9, 0);
      tick('t1', 20000); // +10 s, día 25
      wrapped.recordAppOpen();

      final day24 = await wrapped.dayTotals('20261124');
      final day25 = await wrapped.dayTotals('20261125');

      expect(day24.minutes, 0.2);
      expect(day24.opens, 0);

      expect(day25.minutes, 0.2);
      // La reproducción la cuenta el acumulador por canción que YA existía
      // (umbral de 15 s): las dos muestras de 10 s suman 20 s y caen en el día
      // del reloj. Lo que se separa por día son las minutas y las aperturas.
      expect(day25.plays, 1);
      expect(day25.opens, 1, reason: 'la apertura contó en el día del reloj');
    });

    test(
      'el total sobrevive el reinicio de la app (hidrata del disco)',
      () async {
        tick('t1', 0);
        tick('t1', 10000);
        wrapped.recordAppOpen();
        await wrapped.persistNow();
        wrapped.resetForTesting();
        wrapped.clockForTesting = () => clockNow;

        final totals = await wrapped.dayTotals('20261124');
        expect(totals.minutes, 0.2);
        expect(totals.opens, 1);
      },
    );
  });

  group('forma exacta del cuerpo', () {
    test('ruta del contrato + JSON plano con las claves de la app', () async {
      tick('t1', 0);
      tick('t1', 10000);
      tick('t1', 20000);
      tick('t1', 30000);
      wrapped.recordAppOpen();

      expect(await service.reportNow(), true);
      expect(transport.requests.length, 1);

      final request = transport.requests.single;
      // La ruta del contrato sobre el prefijo REST que la app ya usa.
      expect(request.path, 'metrics/uid_test/daily');
      final tierInputs = RelayTierInputs(
        lanHost: '',
        lanPort: '8080',
        emulator: false,
        lanReachable: null,
        cloudHost: 'api.inutix.com',
      );
      final fullUrl = RelayTierSelector.urlFor(
        i: tierInputs,
        googleUrl: googleBase,
      );
      expect(
        '$fullUrl/${request.path}',
        'https://api.inutix.com'
            '/v1/projects/inutil-music-app/databases/(default)/documents'
            '/metrics/uid_test/daily',
      );

      // Las claves son exactamente las de esta app en el contrato.
      expect(request.body.keys.toSet(), {
        'musicMinutes',
        'musicPlays',
        'musicOpens',
        'musicPlaylists',
        'musicFavorites',
        'source',
        'day',
      });
      expect(
        request.body['musicMinutes'],
        0.5,
        reason: 'double, minutas del día',
      );
      expect(request.body['musicPlays'], 1);
      expect(request.body['musicOpens'], 1);
      expect(request.body['musicPlaylists'], 3);
      expect(request.body['musicFavorites'], 17);
      expect(request.body['source'], 'music');
      expect(request.body['day'], '20261124');
    });

    test('buildBody manda el acumulado del día, no un delta', () {
      final body = DailyUsageReportService.buildBody(
        dayKey: '20261124',
        minutes: 42.5,
        plays: 12,
        opens: 3,
        playlists: 2,
        favorites: 17,
      );
      expect(body, {
        'musicMinutes': 42.5,
        'musicPlays': 12,
        'musicOpens': 3,
        'musicPlaylists': 2,
        'musicFavorites': 17,
        'source': 'music',
        'day': '20261124',
      });
    });
  });

  group('una escritura al día, idempotente', () {
    test('el segundo cierre del mismo día ya no escribe', () async {
      tick('t1', 0);
      tick('t1', 10000);
      wrapped.recordAppOpen();

      expect(await service.reportNow(), true);
      expect(await service.reportNow(), false);
      expect(await service.reportNow(), false);
      expect(transport.requests.length, 1, reason: 'máximo 1 por día');
      expect(await service.isDayReported('20261124'), true);
    });

    test('el marker sobrevive a un reinicio de la app', () async {
      tick('t1', 0);
      tick('t1', 10000);
      wrapped.recordAppOpen();
      expect(await service.reportNow(), true);

      // Mismos prefs, servicio nuevo: el marker está en disco, no en la memoria
      // de la app, porque el límite es una escritura por DÍA.
      final restarted = buildService();
      expect(await restarted.reportNow(), false);
      expect(transport.requests.length, 1);
    });

    test(
      'reenviar el mismo total es idempotente: el reintento manda el mismo cuerpo',
      () async {
        tick('t1', 0);
        tick('t1', 10000);
        wrapped.recordAppOpen();

        // El primer intento falla (el relay respondió 500): el día NO se marcó,
        // o sea quedó pendiente para el siguiente momento de cierre.
        transport.statusCode = 500;
        expect(await service.reportNow(), false);

        // El siguiente cierre manda el MISMO total: el relay hace merge por
        // columna, así que reenviar es seguro.
        transport.statusCode = 200;
        expect(await service.reportNow(), true);

        expect(transport.requests.length, 2);
        expect(
          transport.requests.first.body,
          transport.requests.last.body,
          reason: 'reenviar el mismo acumulado es idempotente',
        );
        expect(transport.requests.first.path, transport.requests.last.path);

        // Y después del éxito el día queda cerrado.
        expect(await service.reportNow(), false);
        expect(transport.requests.length, 2);
      },
    );

    test(
      'el día siguiente escribe de nuevo, con sus propios totales',
      () async {
        tick('t1', 0);
        tick('t1', 10000); // +10 s, día 24
        wrapped.recordAppOpen();
        expect(await service.reportNow(), true);

        clockNow = DateTime.utc(2026, 11, 25, 9, 0);
        tick('t1', 20000); // +10 s, día 25
        expect(await service.reportNow(), true);

        expect(transport.requests.length, 2);
        expect(transport.requests.last.body['day'], '20261125');
        // El día 25 no arrastra lo del 24: cada día reporta lo suyo.
        expect(transport.requests.last.body['musicMinutes'], 0.2);
        expect(transport.requests.last.body['musicOpens'], 0);
      },
    );
  });

  group('ruta por el relay (no se inventa escritura contra Google)', () {
    test('el endpoint existe en el relay LAN y en los nodos de inutix.com', () {
      expect(
        DailyUsageReportService.dailyRouteAvailable(
          tier: RelayTier.lanRelay,
          endpointHost: '192.168.100.27',
        ),
        true,
      );
      expect(
        DailyUsageReportService.dailyRouteAvailable(
          tier: RelayTier.cloudRelay,
          endpointHost: 'api.inutix.com',
        ),
        true,
      );
      expect(
        DailyUsageReportService.dailyRouteAvailable(
          tier: RelayTier.backupRelay,
          endpointHost: 'backup.inutix.com',
        ),
        true,
      );
    });

    test('el Worker workers.dev y Google NO tienen el endpoint', () {
      expect(
        DailyUsageReportService.dailyRouteAvailable(
          tier: RelayTier.cloudRelay,
          endpointHost: 'inutil-cloud-relay.scada-xiaomi-server.workers.dev',
        ),
        false,
        reason: 'el Worker sólo conoce metrics/<uid>/events',
      );
      expect(
        DailyUsageReportService.dailyRouteAvailable(
          tier: RelayTier.google,
          endpointHost: 'firestore.googleapis.com',
        ),
        false,
        reason: 'ahí no hay ruta de métricas que responder',
      );
    });

    test('sin ruta por el relay no se manda nada', () async {
      tick('t1', 0);
      tick('t1', 10000);
      wrapped.recordAppOpen();

      final googleService = buildService(
        dataTier: () => RelayTier.google,
        endpointHost: () => 'firestore.googleapis.com',
      );
      expect(await googleService.reportNow(), false);
      expect(transport.requests.isEmpty, true);
    });

    test('un día sin actividad no genera escritura', () async {
      // Nada de reproducción, nada de aperturas.
      expect(await service.reportNow(), false);
      expect(transport.requests.isEmpty, true);
    });

    test('sin sesión no se manda (el mismo gate de siempre)', () async {
      tick('t1', 0);
      tick('t1', 10000);
      wrapped.recordAppOpen();

      final noSession = buildService(
        currentUid: () => null,
        canSync: () => false,
      );
      expect(await noSession.reportNow(), false);
      expect(transport.requests.isEmpty, true);
    });
  });
}

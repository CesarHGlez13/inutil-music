import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/firebase/firebase_config.dart';
import 'package:inutil_music/core/firebase/relay_tier_selector.dart';

/// Pruebas del selector de tier de datos (LAN S7 → Worker cloud → Google).
///
/// El problema que resuelven: `FirebaseConfig.relayAwareUrl` solo conocía dos
/// estados — el relay LAN del S7 o Google — y además construía
/// `'http://host:puerto'`. Un build horneado con
/// `--dart-define=FB_RELAY_HOST=192.168.100.27` fuera de la LAN de la casa
/// terminaba SIEMPRE en Google y pagaba la cuota entera (medido: 94,114
/// lecturas/día contra los 50,000 del plan Spark = 188 %). La tercera capa es
/// el Worker `inutil_cloud_relay`
/// (`https://inutil-cloud-relay.scada-xiaomi-server.workers.dev`), que habla el
/// mismo dialecto REST pero es alcanzable desde cualquier red — y no cabe en
/// `'http://host:puerto'` porque es HTTPS sin puerto explícito.
///
/// Todas las funciones aquí son puras: no tocan la red ni el estado de clase,
/// así que la tabla de decisión completa se prueba sin levantar servidores.
void main() {
  const google =
      'https://firestore.googleapis.com/v1/projects/p/databases/(default)/documents';
  const cloudHost = 'inutil-cloud-relay.scada-xiaomi-server.workers.dev';
  const cloudUrl =
      'https://inutil-cloud-relay.scada-xiaomi-server.workers.dev'
      '/v1/projects/p/databases/(default)/documents';

  RelayTierInputs inputs({
    String lanHost = '',
    String lanPort = '8080',
    bool emulator = false,
    bool? lanReachable,
    String cloudHost = '',
    String cloudScheme = 'https',
    String cloudPort = '',
  }) =>
      RelayTierInputs(
        lanHost: lanHost,
        lanPort: lanPort,
        emulator: emulator,
        lanReachable: lanReachable,
        cloudHost: cloudHost,
        cloudScheme: cloudScheme,
        cloudPort: cloudPort,
      );

  group('select (tabla de decisión completa)', () {
    test('build sin relay LAN y sin capa cloud → google', () {
      for (final reachable in [null, true, false]) {
        expect(RelayTierSelector.select(inputs(lanReachable: reachable)),
            RelayTier.google,
            reason: 'reachable=$reachable sin ningún host debe pagar Google');
      }
    });

    test('host LAN horneado y sonda viva → lanRelay en los tres estados', () {
      expect(
        RelayTierSelector.select(
            inputs(lanHost: '192.168.100.27', lanReachable: true)),
        RelayTier.lanRelay,
      );
    });

    test('host LAN horneado, sonda sin medir o caída → cloud si hay capa cloud',
        () {
      for (final reachable in [null, false]) {
        expect(
          RelayTierSelector.select(inputs(
            lanHost: '192.168.100.27',
            lanReachable: reachable,
            cloudHost: cloudHost,
          )),
          RelayTier.cloudRelay,
          reason: 'reachable=$reachable fuera de la LAN debe caer al Worker, '
              'no a Google',
        );
      }
    });

    test('host LAN horneado y sin capa cloud → google (comportamiento actual)',
        () {
      for (final reachable in [null, false]) {
        expect(
          RelayTierSelector.select(
              inputs(lanHost: '192.168.100.27', lanReachable: reachable)),
          RelayTier.google,
          reason: 'sin tercera capa no se cambia nada: esto es aditivo',
        );
      }
    });

    test('host LAN en blanco cuenta como no configurado', () {
      expect(
        RelayTierSelector.select(inputs(
          lanHost: '   ',
          lanReachable: true,
          cloudHost: cloudHost,
        )),
        RelayTier.cloudRelay,
      );
      expect(
        RelayTierSelector.select(inputs(lanHost: '   ', lanReachable: true)),
        RelayTier.google,
      );
    });

    test('cloudHost en blanco cuenta como no configurado', () {
      expect(
        RelayTierSelector.select(
            inputs(lanHost: '', lanReachable: null, cloudHost: '  ')),
        RelayTier.google,
      );
    });

    test('el emulador gana sobre los dos relays', () {
      expect(
        RelayTierSelector.select(inputs(
          lanHost: '192.168.100.27',
          lanReachable: true,
          cloudHost: cloudHost,
          emulator: true,
        )),
        RelayTier.google,
        reason: 'ningún relay debe recibir tráfico de emulador',
      );
    });

    test('relay LAN vivo tiene prioridad sobre el cloud incluso con cloudHost',
        () {
      expect(
        RelayTierSelector.select(inputs(
          lanHost: '192.168.100.27',
          lanReachable: true,
          cloudHost: cloudHost,
        )),
        RelayTier.lanRelay,
        reason: 'en casa el S7 es 0 lecturas pagadas; el cloud también cobra '
            'requests de Worker, así que el LAN primero',
      );
    });
  });

  group('urlFor (construcción de endpoint)', () {
    test('tier LAN conserva http + puerto y la ruta exacta de Google', () {
      final url = RelayTierSelector.urlFor(
        i: inputs(lanHost: '192.168.100.27', lanReachable: true),
        googleUrl: google,
      );
      expect(url,
          'http://192.168.100.27:8080/v1/projects/p/databases/(default)/documents');
      expect(Uri.parse(url).path, Uri.parse(google).path,
          reason: 'relay.py y el Worker hablan el mismo dialecto: la ruta '
              'debe ser idéntica o devuelven 404');
      expect(Uri.parse(url).port, 8080);
      expect(Uri.parse(url).scheme, 'http');
    });

    test('tier cloud usa https y NO escribe :puerto cuando cloudPort está vacío',
        () {
      final url = RelayTierSelector.urlFor(
        i: inputs(lanHost: '192.168.100.27', lanReachable: false, cloudHost: cloudHost),
        googleUrl: google,
      );
      expect(url, cloudUrl);
      expect(url.contains(':443'), isFalse,
          reason: 'https://host:443 funciona pero rompe las comparaciones de '
              'string y ensucia el log');
      expect(Uri.parse(url).scheme, 'https');
      expect(Uri.parse(url).host, cloudHost);
      expect(Uri.parse(url).path, Uri.parse(google).path);
    });

    test('cloudPort explícito solo se escribe si el llamante lo pidió', () {
      final url = RelayTierSelector.urlFor(
        i: inputs(cloudHost: '127.0.0.1', cloudScheme: 'http', cloudPort: '8787'),
        googleUrl: google,
      );
      expect(url, 'http://127.0.0.1:8787/v1/projects/p/databases/(default)/documents');
      expect(Uri.parse(url).port, 8787,
          reason: 'el caso real es `wrangler dev` en local');
    });

    test('cloudScheme inventado se normaliza a https, no se inyecta', () {
      for (final scheme in ['HTTPS', ' https ', 'ftp', 'http://evil', '']) {
        final url = RelayTierSelector.urlFor(
          i: inputs(cloudHost: cloudHost, cloudScheme: scheme),
          googleUrl: google,
        );
        expect(url, cloudUrl,
            reason: 'solo http/https son válidos; un texto arbitrario no debe '
                'colar dentro de la URL (scheme=$scheme)');
      }
      expect(
        RelayTierSelector.urlFor(
          i: inputs(cloudHost: cloudHost, cloudScheme: 'http'),
          googleUrl: google,
        ),
        cloudUrl.replaceFirst('https://', 'http://'),
      );
    });

    test('emulador devuelve su URL tal cual, aunque haya cloud configurado', () {
      const emulator =
          'http://127.0.0.1:8080/v1/projects/p/databases/(default)/documents';
      expect(
        RelayTierSelector.urlFor(
          i: inputs(emulator: true, cloudHost: cloudHost),
          googleUrl: google,
          emulatorUrl: emulator,
        ),
        emulator,
      );
      expect(
        RelayTierSelector.urlFor(
          i: inputs(emulator: true, cloudHost: cloudHost),
          googleUrl: google,
        ),
        google,
        reason: 'sin emulatorUrl el fallback es la referencia de Google',
      );
    });

    test('sin cloud y sin LAN devuelve la referencia de Google intacta', () {
      expect(
        RelayTierSelector.urlFor(i: inputs(), googleUrl: google),
        google,
      );
      expect(
        RelayTierSelector.urlFor(
            i: inputs(lanHost: '192.168.100.27', lanReachable: false),
            googleUrl: google),
        google,
      );
    });

    test('ruta derivada desde projectId cuando la referencia viene vacía', () {
      expect(
        RelayTierSelector.cloudUrl(
            inputs(cloudHost: cloudHost), '', 'inutil-music-app', ''),
        'https://$cloudHost'
        '/v1/projects/inutil-music-app/databases/(default)/documents',
      );
    });

    test('ruta de Storage derivada desde el bucket', () {
      expect(
        RelayTierSelector.cloudUrl(
            inputs(cloudHost: cloudHost), '', '', 'inutil-music-app.firebasestorage.app'),
        'https://$cloudHost/v0/b/inutil-music-app.firebasestorage.app/o',
      );
    });

    test('LAN con puerto horneado ilegible cae a 8080, no a un host roto', () {
      expect(
        RelayTierSelector.urlFor(
          i: inputs(lanHost: '192.168.100.27', lanPort: '', lanReachable: true),
          googleUrl: google,
        ),
        'http://192.168.100.27:8080/v1/projects/p/databases/(default)/documents',
      );
    });
  });

  group('cableado en FirebaseConfig', () {
    setUp(() => FirebaseConfig.resetRelayReachability());
    tearDown(() => FirebaseConfig.resetRelayReachability());

    test('sin sonda y sin capa cloud el endpoint es Google, igual que antes',
        () {
      // `FB_CLOUD_RELAY_HOST` se hornea con `String.fromEnvironment`, así que
      // en el entorno de test es `''`: lo que se prueba aquí es que el default
      // NO cambia el comportamiento de los builds que ya existen.
      expect(FirebaseConfig.cloudRelayHost, '');
      expect(FirebaseConfig.cloudRelayUsable, isFalse);
      expect(FirebaseConfig.dataTier, RelayTier.google);
      expect(FirebaseConfig.firestoreBaseUrl, contains('firestore.googleapis'));
      expect(FirebaseConfig.storageBaseUrl, contains('firebasestorage'));
    });

    test('la sonda viva NO redirige si el build no horneó FB_RELAY_HOST', () async {
      // Caso medido el 2026-11-20: `relayHost` es `String.fromEnvironment`,
      // o sea se hornea en COMPILACIÓN y ningún test puede asignarle un host.
      // Por eso, en este entorno, por mucho que la sonda encuentre algo vivo
      // el tier sigue siendo `google`: sin host horneado no hay a dónde
      // redirigir. Esto es lo que protege a los builds publicados sin relay.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final vivo = await FirebaseConfig.probeRelayReachability(
        timeout: const Duration(milliseconds: 400),
        host: '127.0.0.1',
        ports: [server.port],
      );
      expect(vivo, isTrue, reason: 'el puerto bindado sí escucha');
      expect(FirebaseConfig.relayReachabilityState, isTrue);
      expect(FirebaseConfig.relayUsable, isFalse,
          reason: 'sonda viva pero host horneado vacío → relayUsable false');
      expect(FirebaseConfig.dataTier, RelayTier.google);
      expect(FirebaseConfig.firestoreBaseUrl,
          'https://firestore.googleapis.com/v1/projects/'
          '${FirebaseConfig.projectId}/databases/(default)/documents',
          reason: 'byte a byte como antes del cambio de tier');
      expect(FirebaseConfig.storageBaseUrl,
          'https://firebasestorage.googleapis.com/v0/b/'
          '${FirebaseConfig.storageBucket}/o');
    });

    test('un build con host LAN horneado redirige el tier y las dos bases', () {
      // Aquí la decisión se reproduce con los MISMOS inputs que produce
      // `FirebaseConfig.relayTierInputs`, solo que con el host que un build
      // real hornearía (`--dart-define=FB_RELAY_HOST=192.168.100.27`), porque
      // en test ese host no se puede asignar a la clase.
      final i = FirebaseConfig.relayTierInputs;
      const googleDocs =
          'https://firestore.googleapis.com/v1/projects/p/databases/(default)/documents';
      final horneado = RelayTierInputs(
        lanHost: '192.168.100.27',
        lanPort: i.lanPort,
        emulator: false,
        lanReachable: true,
        cloudHost: i.cloudHost,
      );
      expect(RelayTierSelector.select(horneado), RelayTier.lanRelay);
      expect(
        RelayTierSelector.urlFor(i: horneado, googleUrl: googleDocs),
        'http://192.168.100.27:${i.lanPort}'
        '/v1/projects/p/databases/(default)/documents',
      );
      expect(
        Uri.parse(RelayTierSelector.urlFor(i: horneado, googleUrl: googleDocs))
            .path,
        '/v1/projects/p/databases/(default)/documents',
        reason: 'relay.py exige la ruta exacta de Google o devuelve 404',
      );
    });

    test('un build con host cloud horneado cae al Worker cuando el S7 no está',
        () {
      const cloudDocs =
          'https://$cloudHost/v1/projects/p/databases/(default)/documents';
      final offLan = RelayTierInputs(
        lanHost: '192.168.100.27',
        lanPort: '8080',
        emulator: false,
        lanReachable: false,
        cloudHost: cloudHost,
      );
      expect(RelayTierSelector.select(offLan), RelayTier.cloudRelay);
      expect(RelayTierSelector.urlFor(i: offLan, googleUrl: google), cloudDocs);
      expect(RelayTierSelector.urlFor(
        i: offLan,
        googleUrl: 'https://firebasestorage.googleapis.com/v0/b/b/o',
      ), 'https://$cloudHost/v0/b/b/o');
      expect(RelayTierSelector.urlFor(i: offLan, googleUrl: google)
          .contains('firestore.googleapis'), isFalse,
          reason: 'fuera de la LAN NO debe volver a Google: eso es exactamente '
              'lo que paga la cuota');
    });

    test('markRelayUnreachable revierte la decisión del build horneado', () {
      // Mismo fixture "build horneado" que el test anterior, y la caída se
      // simula con el estado que `markRelayUnreachable()` dejaría.
      final vivo = RelayTierInputs(
        lanHost: '192.168.100.27',
        lanPort: '8080',
        emulator: false,
        lanReachable: true,
        cloudHost: '',
      );
      final caido = RelayTierInputs(
        lanHost: '192.168.100.27',
        lanPort: '8080',
        emulator: false,
        lanReachable: false,
        cloudHost: '',
      );
      expect(RelayTierSelector.select(vivo), RelayTier.lanRelay);
      expect(RelayTierSelector.select(caido), RelayTier.google,
          reason: 'sin capa cloud horneada la caída del S7 debe caer a Google');
      expect(FirebaseConfig.relayReachabilityState, isNull,
          reason: 'setUp/tearDown de resetRelayReachability dejan el estado '
              'sin medir, no `false`');
      FirebaseConfig.markRelayUnreachable();
      expect(FirebaseConfig.relayReachabilityState, isFalse);
      FirebaseConfig.resetRelayReachability();
    });

    test('los inputs del tier reflejan el estado real de la clase', () {
      final i = FirebaseConfig.relayTierInputs;
      expect(i.lanHost, FirebaseConfig.relayHost);
      expect(i.lanPort, FirebaseConfig.relayPort);
      expect(i.emulator, FirebaseConfig.useEmulator);
      expect(i.lanReachable, FirebaseConfig.relayReachabilityState);
      expect(i.cloudHost, FirebaseConfig.cloudRelayHost);
      expect(i.cloudScheme, FirebaseConfig.cloudRelayScheme);
      expect(i.cloudPort, FirebaseConfig.cloudRelayPort);
      expect(i.cloudScheme, 'https',
          reason: 'el default debe ser https: el Worker vive en workers.dev '
              'con TLS');
    });

    test('el cloud nunca se usa en emuladores (aunque esté horneado)', () {
      expect(
        RelayTierSelector.select(
          inputs(emulator: true, cloudHost: cloudHost, lanReachable: true),
        ),
        RelayTier.google,
      );
      expect(FirebaseConfig.cloudRelayUsable, isFalse,
          reason: 'en este entorno useEmulator=false y cloudHost vacío, pero '
              'la puerta del cloud es !useEmulator && host no vacío');
    });
  });
}

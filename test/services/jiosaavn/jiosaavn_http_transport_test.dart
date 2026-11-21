import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:inutil_music/services/jiosaavn/jiosaavn_http_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the total deadline aborts a body that keeps sending small chunks',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final client = IoJioSaavnHttpTransport();
      final sockets = <Socket>[];
      final timers = <Timer>[];
      addTearDown(() async {
        for (final timer in timers) {
          timer.cancel();
        }
        await client.close();
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
      });
      var bytesSent = 0;
      final disconnected = Completer<void>();
      final listenerZone = Zone.current.fork(
        specification: ZoneSpecification(
          // Medido con `scratch/repro_accept_error2.dart` (300 corridas del
          // mismo escenario): el ECONNRESET de un `accept()` interrumpido NO
          // sale por el `onError` de la suscripción — salió por
          // `Zone.current.handleUncaughtError`. `dart:io`
          // (`_RawServerSocket.listen`, `dart-sdk/lib/_internal/vm/bin/
          // socket_patch.dart`) construye un `StreamController(sync: true,
          // onCancel: close)` y su manejador nativo hace
          // `controller.addError(e, st); controller.close();`; cuando esa
          // suscripción ya no está viva `dart:async` lo entrega a la ZONA. El
          // `StreamController` captura `Zone.current` al crearse, así que
          // forking la zona alrededor del `listen` sí lo contiene:
          // `accept-error rounds: 17, caught by the forked zone guard: 17,
          // STILL UNCAUGHT: 0, rounds fully clean: 300/300`, frente a
          // `STILL UNCAUGHT: 4` de las mismas 300 corridas en la forma anterior
          // (`onError` sin paraguas), que es exactamente lo que repitió el run
          // `44932442460` con el `onError` de `7063723` ya puesto.
          handleUncaughtError:
              (_, parent, zone, Object error, StackTrace stackTrace) {
                final texto = error.toString();
                final esParteDelAbort =
                    texto.contains('Connection reset by peer') ||
                    texto.contains('Broken pipe') ||
                    texto.contains('SocketException') ||
                    texto.contains('HttpException');
                if (!esParteDelAbort) {
                  // Lo que no sea el abort de un cliente que ya se fue tiene que
                  // seguir llegando a `flutter_test`: este paraguas no es un sitio
                  // donde esconder un bug real.
                  parent.handleUncaughtError(zone, error, stackTrace);
                  return;
                }
                if (!disconnected.isCompleted) disconnected.complete();
              },
        ),
      );
      listenerZone.run(
        () => server.listen(
          (socket) {
            sockets.add(socket);
            Timer? drip;
            void closed() {
              drip?.cancel();
              socket.destroy();
              if (!disconnected.isCompleted) disconnected.complete();
            }

            socket.listen(
              (_) {
                if (drip != null) return;
                socket.write(
                  'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n',
                );
                drip = Timer.periodic(const Duration(milliseconds: 10), (_) {
                  socket.write('1\r\nx\r\n');
                  if (++bytesSent >= 200) closed();
                });
                timers.add(drip!);
              },
              onDone: closed,
              onError: (Object _) => closed(),
            );
          },
          // Se conserva: cubre la entrega por suscripción (`controller.addError`
          // con la suscripción viva), la otra mitad del mismo evento, y
          // completa `disconnected` si el reset llega antes de aceptar nada.
          onError: (Object error) {
            if (!disconnected.isCompleted) disconnected.complete();
          },
        ),
      );
      final elapsed = Stopwatch()..start();
      await expectLater(
        client.get(
          Uri.parse('http://127.0.0.1:${server.port}/slow-header'),
          maximumBytes: 4096,
          readPrefix: true,
          timeout: const Duration(milliseconds: 150),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(elapsed.elapsed, lessThan(const Duration(seconds: 1)));
      await disconnected.future.timeout(const Duration(seconds: 1));
      expect(bytesSent, lessThan(200));
    },
  );

  test(
    'a CDN that ignores Range is read only up to the requested prefix',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = IoJioSaavnHttpTransport();
      addTearDown(() async {
        await client.close();
        await server.close(force: true);
      });
      server.listen((request) async {
        request.response.contentLength = 256 * 1024;
        request.response.add(Uint8List(256 * 1024));
        try {
          await request.response.close();
        } on HttpException {
          // Prefix consumption deliberately closes an ignored-range response.
        }
      });
      final response = await client.get(
        Uri.parse('http://127.0.0.1:${server.port}/audio'),
        maximumBytes: 4096,
        readPrefix: true,
      );
      expect(response.statusCode, 200);
      expect(response.body, hasLength(4096));
      expect(response.headers['content-length'], '${256 * 1024}');
    },
  );

  test(
    'oversized API responses are rejected instead of being fully buffered',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = IoJioSaavnHttpTransport();
      addTearDown(() async {
        await client.close();
        await server.close(force: true);
      });
      server.listen((request) async {
        request.response.contentLength = 1024;
        request.response.add(Uint8List(1024));
        try {
          await request.response.close();
        } on HttpException {
          // The client rejects the size from headers and may close the socket.
        }
      });
      await expectLater(
        client.get(
          Uri.parse('http://127.0.0.1:${server.port}/api'),
          maximumBytes: 16,
        ),
        throwsFormatException,
      );
    },
  );

  test('redirects do not make a second request to an unverified URL', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = IoJioSaavnHttpTransport();
    addTearDown(() async {
      await client.close();
      await server.close(force: true);
    });
    final paths = <String>[];
    server.listen((request) async {
      paths.add(request.uri.path);
      request.response.statusCode = 302;
      request.response.headers.set('Location', '/unverified');
      await request.response.close();
    });
    final response = await client.get(
      Uri.parse('http://127.0.0.1:${server.port}/redirect'),
    );
    expect(response.statusCode, 302);
    expect(paths, ['/redirect']);
  });
}

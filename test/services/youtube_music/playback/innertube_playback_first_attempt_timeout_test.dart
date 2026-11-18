import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/services/youtube_music/playback/innertube_client_profile.dart';
import 'package:inutil_music/services/youtube_music/playback/innertube_client_router.dart';
import 'package:inutil_music/services/youtube_music/playback/innertube_playback_service.dart';
import 'package:inutil_music/services/youtube_music/playback/innertube_stream_validator.dart';
import 'package:inutil_music/services/youtube_music/innertube_transport.dart';

/// Medido sobre el perfil primario, el primer intento de `/player` responde en
/// 78-300 ms en un enlace sano, asi que la ventana corta del primer intento
/// solo puede penalizar a un cliente ya bloqueado: su reintento debe conservar
/// el presupuesto completo y la resolucion tiene que seguir teniendo exito.
void main() {
  const videoId = 'dQw4w9WgXcQ';

  Map<String, dynamic> playerResponse() => <String, dynamic>{
    'playabilityStatus': <String, dynamic>{'status': 'OK'},
    'videoDetails': <String, dynamic>{
      'videoId': videoId,
      'title': 'Test',
      'author': 'Inútil Music',
      'lengthSeconds': '120',
    },
    'streamingData': <String, dynamic>{
      'expiresInSeconds': '3600',
      'adaptiveFormats': <Map<String, dynamic>>[
        <String, dynamic>{
          'itag': 140,
          'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
          'bitrate': 129000,
          'contentLength': '2000000',
          'url': 'https://media.example/audio',
        },
      ],
    },
  };

  test(
    'the first player attempt uses the short deadline and its retry the full one',
    () async {
      final transport = _HangingFirstTransport(playerResponse());
      final service = InnerTubePlaybackService(
        transport: transport,
        validator: _OkValidator(),
        router: InnerTubeClientRouter(
          profiles: const [InnerTubeClientRegistry.visionOS],
          primaryKey: 'visionOS',
        ),
        requestTimeout: const Duration(milliseconds: 400),
        firstAttemptTimeout: const Duration(milliseconds: 100),
        retryDelay: (_) async {},
      );
      addTearDown(service.dispose);

      final result = await service.resolve(videoId);

      expect(result.format.itag, 140);
      expect(transport.postCount, 2);
      expect(transport.timeouts, [
        const Duration(milliseconds: 100),
        const Duration(milliseconds: 400),
      ]);
    },
  );

  test('a healthy client resolves on the short first deadline alone', () async {
    final transport = _HangingFirstTransport(
      playerResponse(),
      hangFirst: false,
    );
    final service = InnerTubePlaybackService(
      transport: transport,
      validator: _OkValidator(),
      router: InnerTubeClientRouter(
        profiles: const [InnerTubeClientRegistry.visionOS],
        primaryKey: 'visionOS',
      ),
      requestTimeout: const Duration(seconds: 12),
    );
    addTearDown(service.dispose);

    final result = await service.resolve(videoId);

    expect(result.format.itag, 140);
    expect(transport.postCount, 1);
    expect(transport.timeouts, [const Duration(seconds: 6)]);
  });

  test('firstAttemptTimeout cannot exceed requestTimeout', () {
    expect(
      () => InnerTubePlaybackService(
        transport: _HangingFirstTransport(playerResponse(), hangFirst: false),
        validator: _OkValidator(),
        requestTimeout: const Duration(seconds: 2),
        firstAttemptTimeout: const Duration(seconds: 5),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}

/// Transporte que imita a [IoInnerTubeTransport]: aplica el `timeout` recibido
/// y nunca responde durante el primer intento, como un cliente bloqueado.
final class _HangingFirstTransport implements InnerTubeTransport {
  _HangingFirstTransport(this.response, {this.hangFirst = true});

  final Map<String, dynamic> response;
  final bool hangFirst;
  final timeouts = <Duration?>[];
  int postCount = 0;

  @override
  Future<InnerTubeHttpResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
    Duration? timeout,
  }) async {
    postCount += 1;
    timeouts.add(timeout);
    final operation = postCount == 1 && hangFirst
        ? Future<void>.delayed(const Duration(seconds: 30))
        : Future<void>.value();
    if (timeout == null) {
      await operation;
    } else {
      await operation.timeout(timeout);
    }
    return InnerTubeHttpResponse(
      statusCode: 200,
      body: jsonEncode(response),
    );
  }

  @override
  Future<InnerTubeHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    Duration? timeout,
  }) async {
    throw UnimplementedError();
  }

  @override
  void close() {}
}

final class _OkValidator implements InnerTubeStreamValidator {
  @override
  Future<InnerTubeStreamProbe> validate(
    Uri uri, {
    required Map<String, String> headers,
    int? contentLength,
  }) async {
    return const InnerTubeStreamProbe(
      statusCode: 206,
      elapsed: Duration(milliseconds: 30),
      probedOffset: 0,
      receivedBytes: 32768,
      contentLength: 2000000,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/features/music/presentation/widgets/inutil_canvas_engine.dart';
import 'package:inutil_music/features/music/presentation/widgets/spotify_canvas_video.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('inutil_music/canvas_video');
  const eventChannel = EventChannel('inutil_music/canvas_video/events');

  tearDown(() {
    InutilCanvasEngine.debugOverrideSupported = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(eventChannel, null);
  });

  testWidgets(
    'SpotifyCanvasVideo uses isolated InutilCanvasEngine on Android and renders native Texture',
    (tester) async {
      InutilCanvasEngine.debugOverrideSupported = true;
      final calls = <MethodCall>[];
      TestStreamHandler? streamHandler;
      EventChannelSink? eventSink;

      streamHandler = MockStreamHandler.inline(
        onListen: (arguments, sink) {
          eventSink = sink;
        },
        onCancel: (arguments) {
          eventSink = null;
        },
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventChannel, streamHandler);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            calls.add(call);
            if (call.method == 'create') {
              return <String, dynamic>{'playerId': 7, 'textureId': 42};
            }
            return null;
          });

      Widget buildCanvas({required bool playing, Uri? url}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 560,
            child: SpotifyCanvasVideo(
              url: url ?? Uri.file('/tmp/canvas_sample.mp4'),
              isPlaying: playing,
              startOffset: animatedArtworkIntroOffset,
              durationHint: const Duration(seconds: 30),
              revealDuration: const Duration(milliseconds: 200),
            ),
          ),
        ),
      );

      await tester.pumpWidget(buildCanvas(playing: true));
      await tester.pump();

      final createCalls = calls.where((c) => c.method == 'create').toList();
      expect(createCalls, hasLength(1));
      expect(createCalls.first.arguments, containsPair('playing', true));
      expect(
        createCalls.first.arguments,
        containsPair('startOffsetMs', animatedArtworkIntroOffset.inMilliseconds),
      );

      // Antes del primer frame nativo, el video sigue oculto sobre la carátula.
      expect(find.byType(Texture), findsNothing);
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.descendant(
                of: find.byType(SpotifyCanvasVideo),
                matching: find.byType(AnimatedOpacity),
              ).first,
            )
            .opacity,
        0,
      );

      // Simular evento nativo onRenderedFirstFrame() del motor aislado.
      eventSink?.success(<String, dynamic>{
        'playerId': 7,
        'event': 'ready',
        'width': 720.0,
        'height': 1280.0,
        'rotation': 90,
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(Texture), findsOneWidget);
      expect(
        tester.widget<Texture>(find.byType(Texture)).textureId,
        42,
      );

      expect(
        tester
            .widget<AnimatedOpacity>(
              find.descendant(
                of: find.byType(SpotifyCanvasVideo),
                matching: find.byType(AnimatedOpacity),
              ).first,
            )
            .opacity,
        1,
      );
      expect(find.byType(RotatedBox), findsOneWidget);

      // Pausar la canción sincroniza el motor de video sin destruirlo.
      await tester.pumpWidget(buildCanvas(playing: false));
      await tester.pump();
      expect(
        calls.any(
          (c) =>
              c.method == 'setPlaying' &&
              c.arguments['playerId'] == 7 &&
              c.arguments['playing'] == false,
        ),
        isTrue,
      );

      // Desmontar libera limpiamente el reproductor nativo.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        calls.any(
          (c) => c.method == 'dispose' && c.arguments['playerId'] == 7,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

typedef EventChannelSink = MockStreamHandlerEventSink;
typedef TestStreamHandler = MockStreamHandler;

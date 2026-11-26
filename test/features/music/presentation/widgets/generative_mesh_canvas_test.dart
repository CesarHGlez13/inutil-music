import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/features/music/presentation/widgets/generative_mesh_canvas.dart';
import 'package:inutil_music/services/spotify_canvas/spotify_canvas_resolver.dart';

void main() {
  group('SpotifyCanvasResolver & GenerativeMeshCanvas Tests', () {
    test('SpotifyCanvasResolver does not make network calls to spotycovs.lol', () async {
      final requestedUris = <Uri>[];
      final resolver = SpotifyCanvasResolver(
        fetchJson: (uri) async {
          requestedUris.add(uri);
          return null;
        },
        probeMediaSize: (uri) async => null,
      );

      final track = const SpotifyCanvasTrack('Yellow', 'Coldplay', Duration(seconds: 269));
      final result = await resolver.resolve(track);

      expect(result, isNull);
      for (final uri in requestedUris) {
        expect(uri.host.contains('spotycovs'), isFalse,
            reason: 'spotycovs.lol must never be queried');
      }
    });

    testWidgets('GenerativeMeshCanvas renders without crashing even with null/black colors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: GenerativeMeshCanvas(
                primaryColor: Colors.black,
                secondaryColor: null,
                isPlaying: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(GenerativeMeshCanvas), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('GenerativeMeshCanvas adapts colors when accent is provided', (tester) async {
      const customColor = Color(0xFFFF4081);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: GenerativeMeshCanvas(
                primaryColor: customColor,
                secondaryColor: Color(0xFF00E5FF),
                isPlaying: false,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(GenerativeMeshCanvas), findsOneWidget);
    });
  });
}

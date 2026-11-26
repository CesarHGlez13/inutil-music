import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/features/music/domain/entities/track_info.dart';
import 'package:inutil_music/features/music/presentation/widgets/hum_search_sheet.dart';

void main() {
  testWidgets('HumSearchSheet displays prompt text and live waveform UI', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: HumSearchSheet(),
          ),
        ),
      ),
    );

    // Debe mostrar la frase exacta requerida por el diseño
    expect(
      find.text('Di, canta o tararea un fragmento de la canción'),
      findsOneWidget,
    );

    // Debe mostrar el widget visualizador de onda neón
    expect(
      find.byKey(const ValueKey('hum-waveform-visualizer')),
      findsOneWidget,
    );
  });

  testWidgets('HumSearchSheet displays matches when tracks are found', (
    WidgetTester tester,
  ) async {
    const testTrack = TrackInfo(
      id: 'test_vid_123',
      title: 'Bohemian Rhapsody',
      artist: 'Queen',
      album: 'A Night at the Opera',
      url: 'https://youtube.com/watch?v=test_vid_123',
      duration: Duration(minutes: 5, seconds: 55),
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: HumSearchSheet(
              initialTracks: [testTrack],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Bohemian Rhapsody'), findsOneWidget);
    expect(find.text('Queen'), findsOneWidget);
  });
}

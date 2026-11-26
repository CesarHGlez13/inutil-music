import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/features/music/presentation/widgets/player_gestures_wrapper.dart';

void main() {
  group('PlayerGesturesWrapper Tests', () {
    testWidgets('Swipe left calls onNextTrack', (tester) async {
      var nextCalled = false;
      var prevCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerGesturesWrapper(
              onNextTrack: () => nextCalled = true,
              onPreviousTrack: () => prevCalled = true,
              child: const SizedBox(width: 400, height: 800),
            ),
          ),
        ),
      );

      // Swipe left
      await tester.drag(find.byType(PlayerGesturesWrapper), const Offset(-150, 0));
      await tester.pumpAndSettle();

      expect(nextCalled, isTrue);
      expect(prevCalled, isFalse);
    });

    testWidgets('Horizontal drag moves child with translation', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerGesturesWrapper(
              child: const SizedBox(
                key: ValueKey('test-child'),
                width: 400,
                height: 800,
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(const Offset(200, 400));
      // First move beyond slop
      await gesture.moveBy(const Offset(-25, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump();

      final transformFinder = find.descendant(
        of: find.byType(PlayerGesturesWrapper),
        matching: find.byType(Transform),
      );
      expect(transformFinder, findsWidgets);

      final transform = tester.widget<Transform>(transformFinder.first);
      expect(transform.transform.getTranslation().x, lessThan(0));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('Swipe right calls onPreviousTrack', (tester) async {
      var nextCalled = false;
      var prevCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerGesturesWrapper(
              onNextTrack: () => nextCalled = true,
              onPreviousTrack: () => prevCalled = true,
              child: const SizedBox(width: 400, height: 800),
            ),
          ),
        ),
      );

      // Swipe right
      await tester.drag(find.byType(PlayerGesturesWrapper), const Offset(150, 0));
      await tester.pumpAndSettle();

      expect(prevCalled, isTrue);
      expect(nextCalled, isFalse);
    });

    testWidgets('Swipe down calls onMinimize', (tester) async {
      var minimizeCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerGesturesWrapper(
              onMinimize: () => minimizeCalled = true,
              child: const SizedBox(width: 400, height: 800),
            ),
          ),
        ),
      );

      // Swipe down
      await tester.drag(find.byType(PlayerGesturesWrapper), const Offset(0, 150));
      await tester.pumpAndSettle();

      expect(minimizeCalled, isTrue);
    });

    testWidgets('Swipe up calls onOpenLyrics', (tester) async {
      var lyricsCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerGesturesWrapper(
              onOpenLyrics: () => lyricsCalled = true,
              child: const SizedBox(width: 400, height: 800),
            ),
          ),
        ),
      );

      // Swipe up
      await tester.drag(find.byType(PlayerGesturesWrapper), const Offset(0, -150));
      await tester.pumpAndSettle();

      expect(lyricsCalled, isTrue);
    });

    testWidgets('Double tap right calls onSeekRelative with +10s and shows ripple', (tester) async {
      Duration? seekDuration;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: PlayerGesturesWrapper(
                onSeekRelative: (dur) => seekDuration = dur,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );

      // Double tap right half (x = 300, y = 400)
      final rightTarget = tester.getTopLeft(find.byType(PlayerGesturesWrapper)) + const Offset(300, 400);
      await tester.tapAt(rightTarget);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(rightTarget);
      await tester.pump();

      expect(seekDuration, equals(const Duration(seconds: 10)));
      expect(find.text('+10s'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 800));
    });

    testWidgets('Double tap left calls onSeekRelative with -10s and shows ripple', (tester) async {
      Duration? seekDuration;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: PlayerGesturesWrapper(
                onSeekRelative: (dur) => seekDuration = dur,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );

      // Double tap left half (x = 100, y = 400)
      final leftTarget = tester.getTopLeft(find.byType(PlayerGesturesWrapper)) + const Offset(100, 400);
      await tester.tapAt(leftTarget);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(leftTarget);
      await tester.pump();

      expect(seekDuration, equals(const Duration(seconds: -10)));
      expect(find.text('-10s'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 800));
    });

    testWidgets('Rapid multiple double taps accumulate seek duration', (tester) async {
      final seekDurations = <Duration>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: PlayerGesturesWrapper(
                onSeekRelative: (dur) => seekDurations.add(dur),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );

      final rightTarget = tester.getTopLeft(find.byType(PlayerGesturesWrapper)) + const Offset(300, 400);
      
      // First double tap: +10s
      await tester.tapAt(rightTarget);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(rightTarget);
      await tester.pump();

      expect(find.text('+10s'), findsOneWidget);

      // Third tap quickly after: becomes +20s
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(rightTarget);
      await tester.pump();

      expect(find.text('+20s'), findsOneWidget);
      expect(seekDurations, contains(const Duration(seconds: 10)));
      expect(seekDurations, contains(const Duration(seconds: 20)));

      await tester.pump(const Duration(milliseconds: 800));
    });
  });
}

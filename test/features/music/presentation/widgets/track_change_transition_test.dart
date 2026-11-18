import 'package:inutil_music/features/music/presentation/widgets/track_change_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'fades out outgoing metadata before incoming metadata appears so text never overlaps',
    (tester) async {
      var identity = 'first';
      late StateSetter update;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return TrackChangeTransition(
                identity: identity,
                child: SizedBox(
                  key: ValueKey('transition-content-$identity'),
                  width: 80,
                  height: 80,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      update(() => identity = 'second');
      await tester.pump();
      // At 45% through the 300ms transition (135ms), outgoing is already 0.0
      // while incoming is fading in cleanly.
      await tester.pump(const Duration(milliseconds: 150));

      Finder nearestAncestor(String value, Type type) {
        final candidates = find
            .ancestor(
              of: find.byKey(ValueKey('transition-content-$value')),
              matching: find.byWidgetPredicate(
                (widget) => widget.runtimeType == type,
              ),
            )
            .evaluate();
        final nearest = candidates.reduce(
          (current, candidate) =>
              candidate.depth > current.depth ? candidate : current,
        );
        return find.byElementPredicate(
          (element) => identical(element, nearest),
        );
      }

      Opacity opacityFor(String value) =>
          tester.widget<Opacity>(nearestAncestor(value, Opacity));
      FractionalTranslation translationFor(String value) =>
          tester.widget<FractionalTranslation>(
            nearestAncestor(value, FractionalTranslation),
          );

      expect(opacityFor('first').opacity, 0);
      expect(opacityFor('second').opacity, greaterThan(0));
      expect(opacityFor('second').opacity, lessThan(1));
      expect(translationFor('second').translation.dy, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rapidly returning to a song keeps transition keys unique', (
    tester,
  ) async {
    var identity = 'first';
    late StateSetter update;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return TrackChangeTransition(
              identity: identity,
              child: SizedBox(
                key: ValueKey('rapid-$identity'),
                width: 80,
                height: 80,
              ),
            );
          },
        ),
      ),
    );

    update(() => identity = 'second');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    update(() => identity = 'first');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byKey(const ValueKey('rapid-first')), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('disables the song transition when reduced motion is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const TrackChangeTransition(
          identity: 'reduced-motion-song',
          switcherKey: ValueKey('reduced-motion-transition'),
          child: SizedBox(width: 80, height: 80),
        ),
      ),
    );

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byKey(const ValueKey('reduced-motion-transition')),
    );
    expect(switcher.duration, Duration.zero);
    expect(switcher.reverseDuration, Duration.zero);
  });
}

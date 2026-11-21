import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/features/music/presentation/widgets/player_panel.dart';

void main() {
  group('PlayerPanel opening transition to fullscreen Canvas', () {
    test(
      'in-flight Canvas or video preview lookup counts as pending Canvas on frame 1',
      () {
        expect(
          playerShouldHoldCanvasLayoutWhilePending(
            hasResolvedVideoUrl: false,
            canvasLookupLoading: true,
          ),
          isTrue,
        );
        expect(
          playerShouldHoldCanvasLayoutWhilePending(
            hasResolvedVideoUrl: true,
            canvasLookupLoading: false,
          ),
          isTrue,
        );
        expect(
          playerShouldHoldCanvasLayoutWhilePending(
            hasResolvedVideoUrl: false,
            canvasLookupLoading: false,
          ),
          isFalse,
        );
      },
    );

    test(
      'opening from collapsed or idle suppresses the 850ms crossfade ghosting',
      () {
        // Player was mounted collapsed off-screen (`wasVisualActive: false`)
        // or had no track (`hadTrack: false`): switching to Canvas on open must
        // be instantaneous so the standard square-artwork layout never ghosts
        // over the fullscreen Canvas player.
        expect(
          playerCanvasModeSwitchDuration(
            disableAnimations: false,
            wasVisualActive: false,
            hadTrack: true,
            hadActiveCanvasVideo: false,
            isEnteringCanvas: true,
          ),
          Duration.zero,
        );
        expect(
          playerCanvasModeSwitchDuration(
            disableAnimations: false,
            wasVisualActive: true,
            hadTrack: false,
            hadActiveCanvasVideo: false,
            isEnteringCanvas: true,
          ),
          Duration.zero,
        );
        // Falling back from an in-flight lookup that resolved to null before
        // any Canvas video played also switches cleanly without 850ms ghosting.
        expect(
          playerCanvasModeSwitchDuration(
            disableAnimations: false,
            wasVisualActive: true,
            hadTrack: true,
            hadActiveCanvasVideo: false,
            isEnteringCanvas: false,
          ),
          Duration.zero,
        );
      },
    );

    test(
      'steady-state player with active track keeps smooth crossfade between modes',
      () {
        expect(
          playerCanvasModeSwitchDuration(
            disableAnimations: false,
            wasVisualActive: true,
            hadTrack: true,
            hadActiveCanvasVideo: true,
            isEnteringCanvas: true,
          ),
          const Duration(milliseconds: 850),
        );
        expect(
          playerCanvasModeSwitchDuration(
            disableAnimations: false,
            wasVisualActive: true,
            hadTrack: true,
            hadActiveCanvasVideo: true,
            isEnteringCanvas: false,
          ),
          const Duration(milliseconds: 650),
        );
        expect(
          playerCanvasModeSwitchDuration(
            disableAnimations: true,
            wasVisualActive: true,
            hadTrack: true,
            hadActiveCanvasVideo: true,
            isEnteringCanvas: true,
          ),
          Duration.zero,
        );
      },
    );

    testWidgets(
      'AnimatedSwitcher with Duration.zero removes previous layout immediately without ghosting',
      (tester) async {
        final duration = playerCanvasModeSwitchDuration(
          disableAnimations: false,
          wasVisualActive: false,
          hadTrack: true,
          hadActiveCanvasVideo: false,
          isEnteringCanvas: true,
        );
        final reverseDuration = playerCanvasModeSwitchDuration(
          disableAnimations: false,
          wasVisualActive: false,
          hadTrack: true,
          hadActiveCanvasVideo: false,
          isEnteringCanvas: false,
        );

        Widget buildSwitcher(bool canvasMode) => MaterialApp(
          home: AnimatedSwitcher(
            duration: duration,
            reverseDuration: reverseDuration,
            child: canvasMode
                ? const SizedBox.expand(key: ValueKey('player-mode-canvas'))
                : const SizedBox.expand(key: ValueKey('player-mode-standard')),
          ),
        );

        await tester.pumpWidget(buildSwitcher(false));
        expect(
          find.byKey(const ValueKey('player-mode-standard')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('player-mode-canvas')), findsNothing);

        await tester.pumpWidget(buildSwitcher(true));
        expect(
          find.byKey(const ValueKey('player-mode-canvas')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('player-mode-standard')),
          findsNothing,
        );
      },
    );
  });
}

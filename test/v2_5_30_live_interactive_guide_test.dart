import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/features/music/presentation/widgets/inutil_onboarding_tour.dart';
import 'package:inutil_music/features/music/presentation/widgets/inutix_live_guide.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    InutixLiveGuideController.instance.resetForTesting();
  });

  tearDown(() {
    InutixLiveGuideController.instance.resetForTesting();
  });

  testWidgets(
    'Recorrido interactivo en vivo recorre anclas reales, cambia pestañas y guarda finalización',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final visitedSections = <InutixGuideSection>[];
      var currentSection = InutixGuideSection.home;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              void selectSection(InutixGuideSection next) {
                visitedSections.add(next);
                setState(() => currentSection = next);
              }

              InutixLiveGuideController.instance.attachHost(
                onSelectSection: selectSection,
                readCurrentSection: () => currentSection,
              );

              return Scaffold(
                body: SafeArea(
                  child: Column(
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          KeyedSubtree(
                            key: InutixGuideAnchors.connectButton,
                            child: const Icon(Icons.devices_rounded),
                          ),
                          const SizedBox(width: 8),
                          KeyedSubtree(
                            key: InutixGuideAnchors.accountButton,
                            child: const Icon(Icons.person_rounded),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: <Widget>[
                            KeyedSubtree(
                              key: InutixGuideAnchors.timeMachineChip,
                              child: const Chip(
                                label: Text('Máquina del Tiempo'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            KeyedSubtree(
                              key: InutixGuideAnchors.echoMemoryChip,
                              child: const Chip(label: Text('Echo Memory')),
                            ),
                            const SizedBox(width: 12),
                            KeyedSubtree(
                              key: InutixGuideAnchors.algorithmChip,
                              child: const Chip(label: Text('Algoritmo')),
                            ),
                            const SizedBox(width: 12),
                            KeyedSubtree(
                              key: InutixGuideAnchors.listeningRoomsChip,
                              child: const Chip(label: Text('Salas en vivo')),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: currentSection == InutixGuideSection.player
                            ? Align(
                                alignment: Alignment.bottomRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: InutixGuideAnchorTarget(
                                    id: InutixGuideAnchors.playerShareMomentId,
                                    child: const Icon(Icons.share_outlined),
                                  ),
                                ),
                              )
                            : Center(
                                child: ElevatedButton(
                                  key: const ValueKey('launch-live-tour'),
                                  onPressed: () => InutilOnboardingTour.show(
                                    context,
                                    inactivityDays: 15,
                                  ),
                                  child: Text('Sección: ${currentSection.name}'),
                                ),
                              ),
                      ),
                      KeyedSubtree(
                        key: InutixGuideAnchors.miniPlayer,
                        child: const SizedBox(
                          height: 60,
                          width: double.infinity,
                          child: ColoredBox(color: Colors.black26),
                        ),
                      ),
                      KeyedSubtree(
                        key: InutixGuideAnchors.bottomNav,
                        child: const SizedBox(
                          height: 56,
                          width: double.infinity,
                          child: ColoredBox(color: Colors.black45),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('launch-live-tour')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const ValueKey('inutix-live-spotlight-tour')),
        findsOneWidget,
      );
      expect(find.text('Paso 1 de 11'), findsOneWidget);
      expect(find.text('Comenzar recorrido'), findsOneWidget);

      Future<void> tapNext() async {
        await tester.tap(find.byKey(const ValueKey('live-tour-next')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 400));
      }

      // Recorrer pasos 2..11 verificando transiciones reales (incluyendo reproductor abierto).
      for (var step = 2; step <= 11; step++) {
        await tapNext();
        expect(find.text('Paso $step de 11'), findsOneWidget);
        if (step == 7) {
          expect(find.text('Abrir reproductor'), findsOneWidget);
        }
        if (step == 8) {
          expect(currentSection, InutixGuideSection.player);
          expect(find.text('COMPARTIR MOMENTO · STUDIO'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('share-moment-studio-preview')),
            findsOneWidget,
          );
        }
      }

      // Debe haber navegado realmente por player, search, library y settings.
      expect(visitedSections, contains(InutixGuideSection.player));
      expect(visitedSections, contains(InutixGuideSection.search));
      expect(visitedSections, contains(InutixGuideSection.library));
      expect(visitedSections, contains(InutixGuideSection.settings));

      // Finalizar recorrido y verificar retorno a Inicio + persistencia.
      await tester.tap(find.byKey(const ValueKey('live-tour-finish')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const ValueKey('inutix-live-spotlight-tour')),
        findsNothing,
      );
      expect(currentSection, InutixGuideSection.home);
      expect(await InutilOnboardingTour.shouldShow(), isFalse);
    },
  );

  testWidgets(
    'InutixContextualCoachBanner muestra consejos una vez por sección y permite reiniciarlos',
    (tester) async {
      final guide = InutixLiveGuideController.instance;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Center(child: Text('Contenido')),
                Positioned.fill(
                  child: InutixContextualCoachBanner(
                    bottomOffset: 100,
                    topAligned: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Al entrar a Buscar por primera vez aparece su consejo en vivo.
      await guide.notifySectionEntered(InutixGuideSection.search);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.byKey(const ValueKey('contextual-tip-search_swipe_queue')),
        findsOneWidget,
      );

      // Al pulsar «Entendido» desaparece y no vuelve a salir al reentrar.
      await tester.tap(find.byKey(const ValueKey('contextual-tip-dismiss')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('contextual-tip-search_swipe_queue')),
        findsNothing,
      );

      await guide.notifySectionEntered(InutixGuideSection.search);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('contextual-tip-search_swipe_queue')),
        findsNothing,
      );

      // Al reiniciar consejos desde Ajustes vuelve a aparecer al entrar a Buscar.
      await guide.resetContextualTips();
      await guide.notifySectionEntered(InutixGuideSection.search);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('contextual-tip-search_swipe_queue')),
        findsOneWidget,
      );

      // Desactivar todos los tips silencia incluso secciones nunca vistas.
      await tester.tap(
        find.byKey(const ValueKey('contextual-tip-disable-all')),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await guide.notifySectionEntered(InutixGuideSection.player);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('contextual-tip-player_share_moment')),
        findsNothing,
      );
    },
  );
}

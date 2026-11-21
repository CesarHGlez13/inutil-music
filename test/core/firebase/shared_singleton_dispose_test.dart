import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guardia del `disposeNotifier: false` que
/// `lib/core/firebase/firebase_sync_providers.dart` usa para los dos
/// proveedores que devuelven un singleton global
/// (`InutilAuthService.instance` y `InutilPlaybackSyncService.instance`).
///
/// Por defecto `ChangeNotifierProvider` SÍ desecha al `ChangeNotifier` que
/// crea, así que el primer contenedor que se descarta mata al singleton y
/// cualquier contenedor posterior lo encuentra muerto. GitHub Actions sólo lo
/// veía en el runner de Windows porque ahí sí se ejecutan
/// `test/features/music/presentation/widgets/player_canvas_layout_test.dart`
/// (en Linux están saltados: el producto desactiva el arte remoto en Linux),
/// y cada `testWidgets` arma su propio `ProviderContainer`. El resultado era
/// `ProviderException … A InutilPlaybackSyncService was used after being
/// disposed` dentro de `_SpotifyFullscreenCanvasPlayer.build`.
///
/// Aquí se mide el contrato de Riverpod con un `ChangeNotifier` de prueba, sin
/// Firebase de por medio, para que la regresión se vea también en el CI de
/// Linux, que es donde estas pruebas de lienzo nunca corren.
class SharedProbe extends ChangeNotifier {
  bool sawDispose = false;

  /// `hasListeners` es `@protected` en `ChangeNotifier` y sólo se puede leer
  /// dentro de la subclase, así que se expone desde aqui para poder medirlo.
  bool get probeHasListeners => hasListeners;

  @override
  void dispose() {
    sawDispose = true;
    super.dispose();
  }
}

/// Singleton "adoptado" por Riverpod (comportamiento por defecto).
final SharedProbe sharedOwned = SharedProbe();

/// Singleton global, igual que `InutilPlaybackSyncService.instance`.
final SharedProbe sharedUnowned = SharedProbe();

final ownedProvider = ChangeNotifierProvider<SharedProbe>((ref) => sharedOwned);

final unownedProvider = ChangeNotifierProvider<SharedProbe>(
  (ref) => sharedUnowned,
  disposeNotifier: false,
);

void main() {
  test('sin disposeNotifier:false el contenedor desecha el ChangeNotifier', () {
    final first = ProviderContainer();
    final sub = first.listen(ownedProvider, (_, _) {});
    expect(identical(first.read(ownedProvider), sharedOwned), isTrue);
    expect(
      sharedOwned.sawDispose,
      isFalse,
      reason: 'vivo mientras el contenedor vive',
    );
    sub.close();
    first.dispose();
    expect(
      sharedOwned.sawDispose,
      isTrue,
      reason: 'Riverpod lo desecha al cerrar el contenedor',
    );

    late Object? boom;
    try {
      sharedOwned.addListener(() {});
    } catch (error) {
      boom = error;
    }
    expect(
      boom,
      isA<StateError>(),
      reason: 'el singleton quedó muerto para siempre: así nació el fallo',
    );
    expect(
      boom.toString(),
      contains('was used after being disposed'),
      reason: 'misma forma que el mensaje que soltó GitHub Actions',
    );
  });

  test('con disposeNotifier:false el singleton sobrevive a su contenedor', () {
    void onDidChange() {}
    final first = ProviderContainer();
    final sub = first.listen(unownedProvider, (_, _) {});
    expect(identical(first.read(unownedProvider), sharedUnowned), isTrue);
    sub.close();
    first.dispose();
    expect(
      sharedUnowned.sawDispose,
      isFalse,
      reason: 'Riverpod no es dueño del singleton global',
    );

    // Un singleton desechado no puede volver a oyentes; aquí debe poder.
    sharedUnowned.addListener(onDidChange);
    expect(sharedUnowned.probeHasListeners, isTrue);
    sharedUnowned.removeListener(onDidChange);

    // El segundo contenedor (el "siguiente testWidgets" de la vida real) debe
    // poder volver a suscribirse sin `ProviderException`.
    final second = ProviderContainer();
    final sub2 = second.listen(unownedProvider, (_, _) {});
    expect(identical(second.read(unownedProvider), sharedUnowned), isTrue);
    sub2.close();
    second.dispose();
    expect(
      sharedUnowned.sawDispose,
      isFalse,
      reason: 'ningún contenedor lo desecha mientras sea compartido',
    );
  });
}

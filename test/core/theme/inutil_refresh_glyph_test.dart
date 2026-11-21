import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/theme/inutil_icons.dart';

/// Rasteriza el pintor de un glifo en un lienzo de `lado` píxeles y devuelve
/// la matriz de tinta (`true` donde el trazo cubre más de la mitad del píxel).
Future<List<List<bool>>> _inkGrid(
  WidgetTester tester,
  InutilGlyph glyph,
  int lado,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InutilIcon(glyph, size: lado.toDouble(), color: Colors.white),
      ),
    ),
  );
  await tester.pump();

  final painter = tester
      .widget<CustomPaint>(
        find.descendant(
          of: find.byType(InutilIcon),
          matching: find.byType(CustomPaint),
        ),
      )
      .painter!;

  // `toByteData` es I/O real de Skia: fuera de runAsync el reloj falso de
  // flutter_test nunca lo deja terminar.
  final bytes = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    painter.paint(canvas, Size.square(lado.toDouble()));
    final image = recorder.endRecording().toImageSync(lado, lado);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data;
  });

  final grid = List.generate(
    lado,
    (_) => List<bool>.filled(lado, false, growable: false),
  );
  for (int y = 0; y < lado; y++) {
    for (int x = 0; x < lado; x++) {
      final alpha = bytes!.getUint8((y * lado + x) * 4 + 3);
      grid[y][x] = alpha > 128;
    }
  }
  return grid;
}

int _count(List<List<bool>> g) =>
    g.fold<int>(0, (a, r) => a + r.where((p) => p).length);

void main() {
  testWidgets('el glifo refresh es punto-simétrico: dos arcos con dos puntas', (
    tester,
  ) async {
    const lado = 48;
    final grid = await _inkGrid(tester, InutilGlyph.refresh, lado);

    int desviaciones = 0;
    for (int y = 0; y < lado; y++) {
      for (int x = 0; x < lado; x++) {
        if (grid[y][x] != grid[lado - 1 - y][lado - 1 - x]) desviaciones++;
      }
    }
    final tinta = _count(grid);
    // 48×48 = 2304 píxeles; un glifo de trazo 1.85/24 ocupa entre ~10 % y ~40 %.
    expect(tinta, greaterThan(250));
    expect(tinta, lessThan(900));
    // La geometría es exactamente simétrica respecto a (12, 12); sólo se
    // tolera el redondeo del anti-aliasing de Skia (8 píxeles midieron en
    // esta máquina). Un glifo de un solo arco con una sola punta —el diseño
    // anterior— desviaba más de 100 píxeles y sí fallaría esta prueba.
    expect(desviaciones, lessThan(30));
  });

  testWidgets('el glifo refresh llena los cuatro cuadrantes', (tester) async {
    const lado = 48;
    final grid = await _inkGrid(tester, InutilGlyph.refresh, lado);
    final mitad = lado ~/ 2;
    final cuadrantes = [
      _count([for (int y = 0; y < mitad; y++) grid[y].sublist(0, mitad)]),
      _count([for (int y = 0; y < mitad; y++) grid[y].sublist(mitad, lado)]),
      _count([for (int y = mitad; y < lado; y++) grid[y].sublist(0, mitad)]),
      _count([for (int y = mitad; y < lado; y++) grid[y].sublist(mitad, lado)]),
    ];
    for (final c in cuadrantes) {
      expect(c, greaterThan(40), reason: 'cuadrante vacío: $cuadrantes');
    }
  });

  testWidgets('el glifo refresh no se recorta en su caja de 24u', (
    tester,
  ) async {
    const lado = 48;
    final grid = await _inkGrid(tester, InutilGlyph.refresh, lado);
    int minx = lado, maxx = -1, miny = lado, maxy = -1;
    for (int y = 0; y < lado; y++) {
      for (int x = 0; x < lado; x++) {
        if (!grid[y][x]) continue;
        if (x < minx) minx = x;
        if (x > maxx) maxx = x;
        if (y < miny) miny = y;
        if (y > maxy) maxy = y;
      }
    }
    // Margen de al menos un píxel de borde a 48 px (= 0.5 u a 24 u).
    expect(minx, greaterThan(0));
    expect(miny, greaterThan(0));
    expect(maxx, lessThan(lado - 1));
    expect(maxy, lessThan(lado - 1));
  });
}

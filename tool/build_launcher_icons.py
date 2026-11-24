#!/usr/bin/env python3
"""Genera los iconos del launcher Android a partir del arte oficial de Inutix Music.

El repo arrastraba el icono por defecto de la plantilla de Flutter
(mipmap-*/ic_launcher.png = robot de Android + logo de Flutter).  Este script
produce:

* `res/mipmap-anydpi-v26/ic_launcher.xml`  -> icono adaptativo (API 26+).
* `res/values/ic_launcher_background.xml`  -> color de fondo de la capa de fondo.
* `res/mipmap-<dpi>/ic_launcher_foreground.png` -> capa frontal en la zona segura.
* `res/mipmap-<dpi>/ic_launcher.png` -> icono heredado para API < 26.
* `res/mipmap-<dpi>/ic_launcher_round.png` -> variante redonda.

Uso:
  python3 tool/build_launcher_icons.py
  # requiere Pillow; revisa el resultado con:
  #   flutter build apk --release --target-platform android-arm64
  # y dentro del APK: `strings resources.arsc | grep ic_launcher` (AGP acorta
  # las rutas a res/XX.png, así que se comprueba por dimensiones, no por nombre).

Fuentes: `assets/icons/inutil_icon.png` (logotipo transparente 512x512) y, para
el color de fondo, el mediano de los píxeles oscuros del icono ya publicado en
iOS (`ios/.../Icon-App-1024x1024@1x.png`), de modo que el launcher Android
coincida con la marca de iOS/Windows.
"""
from __future__ import annotations

import os
from collections import Counter

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
LOGO = os.path.join(ROOT, "assets", "icons", "inutil_icon.png")
IOS_ICON = os.path.join(
    ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset", "Icon-App-1024x1024@1x.png"
)
# dpi -> (lado del icono legado, lado de la capa adaptativa 108dp).
DENSITIES = {"mdpi": (48, 108), "hdpi": (72, 162), "xhdpi": (96, 216), "xxhdpi": (144, 324), "xxxhdpi": (192, 432)}
SAFE_RATIO = 0.62  # fracción del lienzo 108dp que ocupa el arte (zona segura ~66%)


def background_color() -> tuple[int, int, int]:
    img = Image.open(IOS_ICON).convert("RGB")
    px = img.load()
    dark = Counter()
    for y in range(0, img.height, 4):
        for x in range(0, img.width, 4):
            r, g, b = px[x, y]
            if max(r, g, b) < 90:
                dark[(r // 8 * 8, g // 8 * 8, b // 8 * 8)] += 1
    if not dark:
        return (14, 15, 19)
    return dark.most_common(1)[0][0]


def fit_logo(logo: Image.Image, box: int) -> Image.Image:
    """Escala el logotipo para que quepa en la zona segura de un lienzo `box`."""
    target = int(box * SAFE_RATIO)
    ratio = min(target / logo.width, target / logo.height)
    size = (max(1, int(logo.width * ratio)), max(1, int(logo.height * ratio)))
    return logo.resize(size, Image.LANCZOS)


def paste_center(canvas: Image.Image, art: Image.Image) -> None:
    canvas.paste(art, ((canvas.width - art.width) // 2, (canvas.height - art.height) // 2), art)


def main() -> None:
    logo = Image.open(LOGO).convert("RGBA")
    bg = background_color()
    hex_bg = "#%02X%02X%02X" % bg
    print(f"color de fondo de marca: {hex_bg}")

    # Capa de fondo como recurso de color + XML del icono adaptativo.
    values_dir = os.path.join(RES, "values")
    os.makedirs(values_dir, exist_ok=True)
    with open(os.path.join(values_dir, "ic_launcher_background.xml"), "w", encoding="utf-8") as fh:
        fh.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<resources>\n"
            f'    <color name="ic_launcher_background">{hex_bg}</color>\n'
            "</resources>\n"
        )

    anydpi = os.path.join(RES, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n"
    )
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        with open(os.path.join(anydpi, name), "w", encoding="utf-8") as fh:
            fh.write(adaptive)

    for dpi, (legacy, adaptive_side) in DENSITIES.items():
        out = os.path.join(RES, f"mipmap-{dpi}")
        os.makedirs(out, exist_ok=True)

        # Capa frontal: arte en la zona segura, resto transparente.
        fg = Image.new("RGBA", (adaptive_side, adaptive_side), (0, 0, 0, 0))
        paste_center(fg, fit_logo(logo, adaptive_side))
        fg.save(os.path.join(out, "ic_launcher_foreground.png"))

        # Icono heredado: lienzo con fondo de marca y esquinas redondeadas
        # (los launchers que no enmascaran lo muestran tal cual).
        for side, fname in ((legacy, "ic_launcher.png"), (legacy, "ic_launcher_round.png")):
            canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
            draw = ImageDraw.Draw(canvas)
            radius = int(side * (0.5 if fname == "ic_launcher_round.png" else 0.22))
            draw.rounded_rectangle((0, 0, side - 1, side - 1), radius=radius, fill=hex_bg)
            paste_center(canvas, fit_logo(logo, side))
            canvas.save(os.path.join(out, fname))
        print(
            f"mipmap-{dpi}: ic_launcher.png {legacy}px, ic_launcher_round.png {legacy}px, "
            f"ic_launcher_foreground.png {adaptive_side}px"
        )

    # Vista previa para revisión visual: heredado, redondo y adaptativo plano.
    preview_side = 192
    canvas = Image.new("RGB", (preview_side * 3, preview_side), (255, 255, 255))
    legacy = Image.open(os.path.join(RES, "mipmap-xxxhdpi", "ic_launcher.png")).convert("RGBA")
    round_ = Image.open(os.path.join(RES, "mipmap-xxxhdpi", "ic_launcher_round.png")).convert("RGBA")
    adaptive_prev = Image.new("RGBA", (preview_side, preview_side), hex_bg)
    paste_center(adaptive_prev, fit_logo(logo, preview_side))
    for i, im in enumerate((legacy, round_, adaptive_prev)):
        canvas.paste(im, (preview_side * i, 0), im)
    preview_dir = os.path.join(ROOT, "scratch")
    os.makedirs(preview_dir, exist_ok=True)
    preview = os.path.join(preview_dir, "launcher_icons_preview.png")
    canvas.save(preview)
    print(f"vista previa: {preview}")


if __name__ == "__main__":
    main()

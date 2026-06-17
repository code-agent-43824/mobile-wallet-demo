#!/usr/bin/env python3
"""Generate the app icon (round white badge + bold black "W") for all platforms.

Replaces Flutter's default launcher icon with a custom one:
- Android (`mipmap-*/ic_launcher.png`) and Windows (`runner/resources/app_icon.ico`):
  a white circle on a transparent background (a true round icon).
- iOS (`Assets.xcassets/AppIcon.appiconset/*`): a white **opaque square** (iOS
  fills transparency with black, and the system squircle-masks the icon).

Run from the repo root with any bold TTF:
    WALLET_ICON_FONT=/path/to/SomeBold.ttf python3 scripts/gen_app_icon.py

Requires Pillow (`pip install Pillow`). Re-run after changing the glyph/letter.
"""

import os

from PIL import Image, ImageDraw, ImageFont

FONT = os.environ.get(
    "WALLET_ICON_FONT",
    "/mnt/skills/examples/canvas-design/canvas-fonts/Outfit-Bold.ttf",
)
LETTER = "W"
WHITE = (255, 255, 255, 255)
BLACK = (0, 0, 0, 255)
CLEAR = (0, 0, 0, 0)
SS = 4  # supersample factor for crisp edges at small sizes


def _fit_font(draw: ImageDraw.ImageDraw, target_w: float) -> ImageFont.FreeTypeFont:
    base = 400
    f = ImageFont.truetype(FONT, base)
    b = draw.textbbox((0, 0), LETTER, font=f)
    return ImageFont.truetype(FONT, max(8, round(base * target_w / (b[2] - b[0]))))


def _draw_letter(img: Image.Image, s: int) -> None:
    d = ImageDraw.Draw(img)
    f = _fit_font(d, s * 0.56)
    b = d.textbbox((0, 0), LETTER, font=f)
    w, h = b[2] - b[0], b[3] - b[1]
    d.text(((s - w) / 2 - b[0], (s - h) / 2 - b[1]), LETTER, font=f, fill=BLACK)


def circle(size: int) -> Image.Image:
    s = size * SS
    img = Image.new("RGBA", (s, s), CLEAR)
    m = round(s * 0.02)
    ImageDraw.Draw(img).ellipse([m, m, s - 1 - m, s - 1 - m], fill=WHITE)
    _draw_letter(img, s)
    return img.resize((size, size), Image.LANCZOS)


def square(size: int) -> Image.Image:  # iOS: opaque, no alpha channel
    s = size * SS
    img = Image.new("RGBA", (s, s), WHITE)
    _draw_letter(img, s)
    return img.resize((size, size), Image.LANCZOS).convert("RGB")


def main() -> None:
    root = os.path.join(os.path.dirname(__file__), "..")
    os.chdir(root)

    for density, s in {
        "mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192,
    }.items():
        circle(s).save(f"android/app/src/main/res/mipmap-{density}/ic_launcher.png")

    ios_dir = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, s in {
        "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60, "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120, "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180, "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152, "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }.items():
        square(s).save(os.path.join(ios_dir, name))

    circle(256).save(
        "windows/runner/resources/app_icon.ico",
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print("Generated app icons for Android, iOS, and Windows.")


if __name__ == "__main__":
    main()

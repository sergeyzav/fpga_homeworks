#!/usr/bin/env python3
"""Render an 8x16 bitmap font (ASCII 0x20..0x7F) from a system monospace TTF into mem/font8x16.hex.
One byte per glyph row, MSB = leftmost pixel; 96 glyphs x 16 rows = 1536 lines.

The committed mem/font8x16.hex is the reference image. Regenerating on another OS (or with another
Pillow / FreeType version) may pick a different font from CANDIDATES or rasterise slightly
differently, so the output is not guaranteed byte-identical; only regenerate deliberately."""
import pathlib
from PIL import Image, ImageDraw, ImageFont

CANDIDATES = ["/System/Library/Fonts/Menlo.ttc", "/System/Library/Fonts/Monaco.ttf",
              "/Library/Fonts/Courier New.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
              "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf"]

# 13 px with the baseline offset 0 is the largest Menlo render whose 96 glyphs (including the
# descenders g j p q y and the bar |) all stay inside the 8x16 cell.
SIZE, Y_OFF = 13, 0

def load_font():
    for path in CANDIDATES:
        if pathlib.Path(path).exists():
            return ImageFont.truetype(path, SIZE), path
    raise SystemExit("no monospace TTF found; add a path to CANDIDATES")

def render_glyph(font, ch):
    img = Image.new("L", (8, 16), 0)
    ImageDraw.Draw(img).text((0, Y_OFF), ch, font=font, fill=255)
    rows = []
    for y in range(16):
        b = 0
        for x in range(8):
            if img.getpixel((x, y)) >= 128:
                b |= 0x80 >> x
        rows.append(b)
    return rows

def build_hex():
    font, path = load_font()
    lines = [f"// 8x16 font, ASCII 0x20..0x7F, 16 bytes per glyph, MSB = left pixel. Source: {path}"]
    for code in range(0x20, 0x80):
        lines += [f"{b:02X}" for b in render_glyph(font, chr(code))]
    return "\n".join(lines) + "\n"

if __name__ == "__main__":
    out = pathlib.Path(__file__).resolve().parents[1] / "mem" / "font8x16.hex"
    out.write_text(build_hex()); print(f"wrote {out}")

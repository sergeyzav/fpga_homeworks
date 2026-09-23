# tools/test_gen_font.py  — run: .venv/bin/python tools/test_gen_font.py
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import gen_font as g

ROOT = pathlib.Path(__file__).resolve().parents[1]
committed = (ROOT / "mem" / "font8x16.hex").read_text()
rows = [l for l in committed.splitlines() if not l.startswith("//")]

def glyph(ch):
    i = (ord(ch) - 0x20) * 16
    return [int(r, 16) for r in rows[i:i + 16]]

assert committed.splitlines()[0].startswith("//"), "first line must be a comment header"
assert len(rows) == 96 * 16, f"expected 1536 glyph rows, got {len(rows)}"
assert all(0 <= int(r, 16) <= 0xFF and len(r) == 2 for r in rows), "every row must be one byte (2 hex digits)"
assert all(b == 0 for b in glyph(" ")), "space must be blank"
assert sum(bin(b).count("1") for b in glyph("#")) > 10, "# must have ink"
assert sum(bin(b).count("1") for b in glyph("A")) > 10, "A must have ink"
assert glyph("A")[0] == 0 and glyph("A")[15] == 0, "A must not touch the top or bottom row of the cell"

# The generator must reproduce the committed image when the same source font is available.
try:
    font, path = g.load_font()
except SystemExit:
    font = path = None
src = committed.splitlines()[0].split("Source: ")[-1]
if path is None or path != src:
    print(f"SKIP regeneration check: reference font {src} not available here (found {path})")
else:
    assert g.build_hex() == committed, "regenerated font differs from committed mem/font8x16.hex; re-run tools/gen_font.py deliberately"
print("PASS test_gen_font")

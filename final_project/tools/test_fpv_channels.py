# tools/test_fpv_channels.py — run: .venv/bin/python tools/test_fpv_channels.py
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import fpv_channels as fc, gen_chan_names as gn, gen_ui_strings as gs

ch = fc.channels()
assert len(ch) == 40 and ch[0] == ("A1", 5865) and ch[39] == ("R8", 5917)
u = fc.unique_channels()
assert len(u) == 39, len(u)
names = [n for n, _, _ in u]
assert "F8" in names and "R7" not in names
f8 = [c for c in u if c[0] == "F8"][0]
assert f8[1] == 5880 and f8[2] == "R7", f8                     # (name, freq, alias)
srt = fc.by_frequency()
assert [f for _, f, _ in srt] == sorted(f for _, f, _ in srt) and srt[0][1] == 5645 and srt[-1][1] == 5945
assert fc.display_name(u[0]) == "A1 5865 " and len(fc.display_name(f8)) == 8

# triple-collision test: a frequency appearing three times must raise ValueError
_orig_bands = fc.BANDS
fc.BANDS = {
    "A": [9999, 1, 2, 3, 4, 5, 6, 7],
    "B": [9999, 8, 9, 10, 11, 12, 13, 14],
    "E": [9999, 15, 16, 17, 18, 19, 20, 21],
    "F": [22, 23, 24, 25, 26, 27, 28, 29],
    "R": [30, 31, 32, 33, 34, 35, 36, 37],
}
try:
    fc.unique_channels()
    raise AssertionError("expected ValueError for triple frequency collision")
except ValueError:
    pass
finally:
    fc.BANDS = _orig_bands

lines = gn.build_hex().splitlines()
data = [l for l in lines if not l.startswith("//")]
assert len(data) == 64 * 8, len(data)
assert bytes(int(x, 16) for x in data[0:8]).decode() == "A1 5865 "
assert all(x == "20" for x in data[39 * 8:64 * 8])            # all padding entries are spaces

sl = [l for l in gs.build_hex().splitlines() if not l.startswith("//")]
assert len(sl) == 16 * 8
assert bytes(int(x, 16) for x in sl[8 * gs.STR_SCAN:8 * gs.STR_SCAN + 8]).decode() == "SCAN    "
assert gs.STR_TEST == 9  # hardcoded in src/display/ui_demo.sv (Task 17)
assert all(x == "20" for x in sl[10 * 8:16 * 8])               # all padding entries are spaces
print("PASS test_fpv_channels")

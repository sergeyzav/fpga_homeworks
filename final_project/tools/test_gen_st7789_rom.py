# tools/test_gen_st7789_rom.py  — run: .venv/bin/python tools/test_gen_st7789_rom.py
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import gen_st7789_rom as g

words = g.build_rom()
assert words[0] == 0x0001, "first word must be SWRESET command"          # type 00, 0x01
assert words[1] == (0b10 << 14) | 150, "SWRESET must be followed by 150 tick delay"
assert (0b00 << 14 | 0x11) in words, "SLPOUT present"
i = words.index(0b00 << 14 | 0x3A)
assert words[i + 1] == (0b01 << 14) | 0x55, "COLMOD parameter must be 0x55 (RGB565)"
i = words.index(0b00 << 14 | 0x2A)
assert words[i + 1:i + 5] == [(0b01 << 14) | b for b in (0x00, 0x00, 0x01, 0x3F)], "CASET 0..319"
i = words.index(0b00 << 14 | 0x2B)
assert words[i + 1:i + 5] == [(0b01 << 14) | b for b in (0x00, 0x00, 0x00, 0xEF)], "RASET 0..239"
assert words[-1] == 0xC000, "last word is END"
assert len(words) <= g.ROM_DEPTH
text = g.format_mem(words)
assert text.splitlines()[0].startswith("//")
assert len([l for l in text.splitlines() if not l.startswith("//")]) == g.ROM_DEPTH
print("PASS test_gen_st7789_rom")

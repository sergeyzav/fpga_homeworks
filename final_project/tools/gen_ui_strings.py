#!/usr/bin/env python3
"""Generate mem/ui_strings.hex: 16 fixed 8-character OSD strings. Indices are shared with ui_ctrl users."""
import pathlib

STR_BLANK, STR_SCAN, STR_LOCK, STR_PAL, STR_NTSC, STR_INIT, STR_FAULT, STR_NOSIG, STR_CH, STR_TEST = range(10)
STRINGS = ["        ", "SCAN    ", "LOCK    ", "PAL     ", "NTSC    ", "INIT    ", "FAULT   ", "NO SIG  ", "CH      ", "TEST    "]
ENTRIES = 16

def build_hex():
    strs = STRINGS + ["        "] * (ENTRIES - len(STRINGS))
    lines = ["// fixed OSD strings ROM: 16 x 8 bytes; index constants in tools/gen_ui_strings.py"]
    for s in strs:
        assert len(s) == 8, s
        lines += [f"{ord(c):02X}" for c in s]
    return "\n".join(lines) + "\n"

if __name__ == "__main__":
    out = pathlib.Path(__file__).resolve().parents[1] / "mem" / "ui_strings.hex"
    out.write_text(build_hex()); print(f"wrote {out}")

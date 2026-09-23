#!/usr/bin/env python3
"""Generate mem/chan_names.hex: 64 entries x 8 ASCII bytes (39 channels + space padding)."""
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import fpv_channels as fc

ENTRIES = 64

def build_hex():
    names = [fc.display_name(c) for c in fc.unique_channels()]
    names += [" " * 8] * (ENTRIES - len(names))
    lines = [f"// channel names ROM: {ENTRIES} x 8 bytes, index = unique channel index (tools/fpv_channels.py)"]
    for n in names:
        assert len(n) == 8, n
        lines += [f"{ord(c):02X}" for c in n]
    return "\n".join(lines) + "\n"

if __name__ == "__main__":
    out = pathlib.Path(__file__).resolve().parents[1] / "mem" / "chan_names.hex"
    out.write_text(build_hex()); print(f"wrote {out}")

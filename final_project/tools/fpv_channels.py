"""Analog FPV 5.8 GHz channel table (bands A/B/E/F/R). Shared by ROM generators."""
from typing import NamedTuple

BANDS = {
    "A": [5865, 5845, 5825, 5805, 5785, 5765, 5745, 5725],
    "B": [5733, 5752, 5771, 5790, 5809, 5828, 5847, 5866],
    "E": [5705, 5685, 5665, 5645, 5885, 5905, 5925, 5945],
    "F": [5740, 5760, 5780, 5800, 5820, 5840, 5860, 5880],
    "R": [5658, 5695, 5732, 5769, 5806, 5843, 5880, 5917],
}


class Channel(NamedTuple):
    name: str
    freq: int
    alias: str = ""


def channels():
    """All 40 (name, freq_mhz) in band order A1..R8."""
    return [(f"{b}{i + 1}", f) for b in "ABEFR" for i, f in enumerate(BANDS[b])]

def unique_channels():
    """39 Channel(name, freq_mhz, alias) with duplicate frequencies merged (F8 5880 == R7).

    Raises ValueError if a frequency appears a third time (the alias slot is already used)."""
    out, seen = [], {}
    for name, f in channels():
        if f in seen:
            i = seen[f]
            if out[i].alias:
                raise ValueError(
                    f"frequency {f} MHz collides three times: {out[i].name}/{out[i].alias}/{name}"
                )
            out[i] = Channel(out[i].name, f, name)
        else:
            seen[f] = len(out)
            out.append(Channel(name, f, ""))
    return out

def by_frequency():
    """39 unique channels sorted ascending by frequency."""
    return sorted(unique_channels(), key=lambda c: c[1])

def display_name(ch):
    """8-character OSD label, e.g. 'A1 5865 '."""
    name, f, _ = ch
    s = f"{name} {f}".ljust(8)
    assert len(s) == 8, s
    return s

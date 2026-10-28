# PROTOTYPE, throwaway: writes <out>/<meeting>/themclean.wav, the Them track muted wherever the
# reference has Me speaking and no Them speaker (padded 0.1 s), to mimic a tapped call where Me
# never reaches the Them stream. Usage: mute_me.py <test set dir> <out dir>
import json
import sys
import wave
from pathlib import Path

import numpy as np

PAD = 0.1
root, out = Path(sys.argv[1]), Path(sys.argv[2])
for m in json.loads((root / "index.json").read_text())["meetings"]:
    if m["me"] is None:
        continue
    d = root / "meetings" / m["id"]
    with wave.open(str(d / "them.wav")) as w:
        params = w.getparams()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).copy()
    me = np.zeros(len(x), dtype=bool)
    them = np.zeros(len(x), dtype=bool)
    for line in (d / "reference" / "timeline.rttm").read_text().splitlines():
        f = line.split()
        s, e = float(f[3]), float(f[3]) + float(f[4])
        if f[7] == m["me"]:
            me[max(0, int((s - PAD) * 16000)):int((e + PAD) * 16000)] = True
        elif f[7] in m["them"]:
            them[int(s * 16000):int(e * 16000)] = True
    mute = me & ~them
    x[mute] = 0
    (out / m["id"]).mkdir(parents=True, exist_ok=True)
    with wave.open(str(out / m["id"] / "themclean.wav"), "wb") as w:
        w.setparams(params)
        w.writeframes(x.tobytes())
    print(m["id"], f"muted {mute.mean():.1%}")

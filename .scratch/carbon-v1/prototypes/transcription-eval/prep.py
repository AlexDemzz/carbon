# PROTOTYPE, throwaway: builds the inputs the transcription eval runs on.
#   <out>/<meeting>/me.wav, them.wav: each stream muted wherever the reference has only the other
#     stream speaking (padded 0.1 s), so neither track carries the headset bleed a real tap or a
#     headphone mic would not hear. Muted stretches are digital zeros, as a muted Carbon stream is.
#   <out>/silence/*.wav: 10 min fixtures for phantom text (zeros, room noise, hold music, ringback).
# Usage: prep.py <test set dir> <out dir>
import json
import sys
import wave
from pathlib import Path

import numpy as np

RATE = 16000
PAD = 0.1
root, out = Path(sys.argv[1]), Path(sys.argv[2])


def read(path):
    with wave.open(str(path)) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).copy()


def write(path, x):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(np.clip(x, -32768, 32767).astype(np.int16).tobytes())


for m in json.loads((root / "index.json").read_text())["meetings"]:
    if m["me"] is None:
        continue
    d = root / "meetings" / m["id"]
    tracks = {s: read(d / f"{s}.wav") for s in ("me", "them")}
    n = len(tracks["me"])
    active = {s: np.zeros(n, dtype=bool) for s in tracks}
    for line in (d / "reference" / "timeline.rttm").read_text().splitlines():
        f = line.split()
        s, e = float(f[3]), float(f[3]) + float(f[4])
        stream = "me" if f[7] == m["me"] else "them" if f[7] in m["them"] else None
        if stream:
            active[stream][max(0, int((s - PAD) * RATE)):int((e + PAD) * RATE)] = True
    for stream, other in (("me", "them"), ("them", "me")):
        mute = active[other] & ~active[stream]
        x = tracks[stream].copy()
        x[mute] = 0
        write(out / m["id"] / f"{stream}.wav", x)
        print(m["id"], stream, f"muted {mute.mean():.1%}")

rng = np.random.default_rng(0)
n = 600 * RATE
t = np.arange(n) / RATE


def pink(n, dbfs):
    spectrum = np.fft.rfft(rng.standard_normal(n))
    spectrum /= np.sqrt(np.maximum(np.arange(len(spectrum)), 1))
    x = np.fft.irfft(spectrum, n)
    return x / np.sqrt(np.mean(x**2)) * 32768 * 10 ** (dbfs / 20)


# A plain I-IV-V-I chord loop with soft attacks: a stand-in for hold music, no copyrighted audio.
chords = [(261.6, 329.6, 392.0), (349.2, 440.0, 523.3), (392.0, 493.9, 587.3), (261.6, 329.6, 392.0)]
music = np.zeros(n)
beat = 2 * RATE
for i in range(n // beat):
    seg = np.arange(beat) / RATE
    env = np.minimum(1, seg / 0.05) * np.exp(-seg * 1.2)
    tone = sum(np.sin(2 * np.pi * f * seg) + 0.3 * np.sin(4 * np.pi * f * seg) for f in chords[i % 4])
    music[i * beat:(i + 1) * beat] = tone * env
music = music / np.abs(music).max() * 32768 * 10 ** (-20 / 20) + pink(n, -60)
# US ringback: 440 + 480 Hz, 2 s on, 4 s off.
ring = (np.sin(2 * np.pi * 440 * t) + np.sin(2 * np.pi * 480 * t)) * ((t % 6) < 2) * 32768 * 10 ** (-26 / 20)

write(out / "silence" / "zeros.wav", np.zeros(n))
write(out / "silence" / "room-noise.wav", pink(n, -55))
write(out / "silence" / "hold-music.wav", music)
write(out / "silence" / "ringback.wav", ring + pink(n, -65))
print("silence fixtures written")

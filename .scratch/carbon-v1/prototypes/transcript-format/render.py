"""PROTOTYPE, throwaway: renders a Carbon Transcript body from real engine output.

Inputs: SpeechTranscriber word timings for the Me and Them streams (transcription-eval hyp/st)
and FluidAudio offline diarization of the Them stream (diarization-eval `diarize`, threshold 0.6).

    python3 render.py <me.json> <them.json> <diarization.json | -> <out.md> [Name=Speaker ...]

`-` instead of a diarization file renders the Me/Them fallback.
Trailing `Speaker B=Sam Rivera` arguments apply renames to the rendered file (write-back rule).
"""
import json
import re
import sys

NEAREST_SEGMENT_S = 1.0  # word-level merge from "Diarization and Voice Print quality on real calls"
SENTENCE_PAUSE_S = 1.5   # a pause this long ends a sentence even without punctuation
TURN_PAUSE_S = 10.0      # same Speaker after this much silence gets a new timestamped turn
MAX_TURN_S = 90.0        # a monologue gets a fresh timestamp at the first sentence end past this
TERMINAL = ".?!…"
HEADER = re.compile(r"^\*\*(?P<speaker>[^*\n]+)\*\* \[(?P<time>\d+:\d{2}(?::\d{2})?)\] ", re.M)


def load_words(path):
    return json.load(open(path))["words"]


def speaker_of(word, segments):
    best, best_overlap = None, 0.0
    for seg in segments:
        overlap = min(word["e"], seg["end"]) - max(word["s"], seg["start"])
        if overlap > best_overlap:
            best, best_overlap = seg["speaker"], overlap
    if best:
        return best
    mid = (word["s"] + word["e"]) / 2
    seg = min(segments, key=lambda g: max(g["start"] - mid, mid - g["end"], 0))
    return seg["speaker"] if max(seg["start"] - mid, mid - seg["end"], 0) <= NEAREST_SEGMENT_S else None


def attribute_them(words, diarization):
    if diarization is None:
        return [dict(w, speaker="Them") for w in words]
    segments = diarization["segments"]
    raw = [speaker_of(w, segments) for w in words]
    # A word no segment reaches keeps the previous Them word's Speaker (the next one's at the start).
    for i in range(len(raw)):
        if raw[i] is None:
            raw[i] = next((raw[j] for j in range(i - 1, -1, -1) if raw[j]), None)
    for i in range(len(raw) - 1, -1, -1):
        if raw[i] is None:
            raw[i] = raw[i + 1]
    # Speaker A, B, C… in order of first word in the Meeting.
    letters = {}
    for cluster in raw:
        letters.setdefault(cluster, f"Speaker {chr(ord('A') + len(letters))}")
    return [dict(w, speaker=letters[c]) for w, c in zip(words, raw)]


def sentences(words):
    out, current = [], []
    for w in words:
        if current and (w["speaker"] != current[-1]["speaker"] or w["s"] - current[-1]["e"] >= SENTENCE_PAUSE_S):
            out.append(current)
            current = []
        current.append(w)
        if w["w"].rstrip("\"')")[-1:] in TERMINAL:
            out.append(current)
            current = []
    if current:
        out.append(current)
    return out


def turns(me_words, them_words):
    units = sentences(me_words) + sentences(them_words)
    # Me first on a tie: the person's own words lead.
    units.sort(key=lambda u: (u[0]["s"], u[0]["speaker"] != "Me"))
    result = []
    for unit in units:
        last = result[-1] if result else None
        if (
            last
            and last["speaker"] == unit[0]["speaker"]
            and unit[0]["s"] - last["end"] < TURN_PAUSE_S
            and not (unit[0]["s"] - last["start"] > MAX_TURN_S)
        ):
            last["words"] += unit
            last["end"] = max(last["end"], unit[-1]["e"])
        else:
            result.append({"speaker": unit[0]["speaker"], "start": unit[0]["s"], "end": unit[-1]["e"], "words": list(unit)})
    return result


def timestamp(seconds):
    s = int(seconds)
    h, m, s = s // 3600, s % 3600 // 60, s % 60
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


def escape(text):
    return re.sub(r"([\\`*_\[\]<>])", r"\\\1", text)


def body(turn_list):
    lines = []
    for t in turn_list:
        text = " ".join(w["w"] for w in t["words"])
        text = text[:1].upper() + text[1:]
        lines.append(f"**{t['speaker']}** [{timestamp(t['start'])}] {escape(text)}")
    return "\n\n".join(lines)


def rename(markdown, old, new):
    """Write-back of a rename: only the label in turn headers changes; turns are never regrouped."""
    return HEADER.sub(lambda m: m.group(0).replace(f"**{old}**", f"**{new}**", 1) if m["speaker"] == old else m.group(0), markdown)


FRONTMATTER = """---
provider: Google Meet
id: abc-defg-hij
date: 2026-10-27T10:00:00-04:00
title: Remote control kickoff
duration: {duration}
participants:
  - Alex Martin <alex@example.com>
  - Sam Rivera <sam@example.com>
  - Priya Nair <priya@example.com>
  - Jordan Lee <jordan@example.com>
---

## Summary

_Placeholder: the Summary format belongs to "On-device summary quality"._

## Transcript

"""


def main():
    me_path, them_path, dia_path, out_path, *renames = sys.argv[1:]
    me = [dict(w, speaker="Me") for w in load_words(me_path)]
    diarization = None if dia_path == "-" else json.load(open(dia_path))
    them = attribute_them(load_words(them_path), diarization)
    duration = json.load(open(me_path))["duration"]
    markdown = FRONTMATTER.format(duration=timestamp(duration)) + body(turns(me, them)) + "\n"
    for pair in renames:
        old, new = pair.split("=", 1)
        markdown = rename(markdown, old, new)
    open(out_path, "w").write(markdown)


if __name__ == "__main__":
    main()

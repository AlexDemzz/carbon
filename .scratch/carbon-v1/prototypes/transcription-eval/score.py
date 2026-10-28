# PROTOTYPE, throwaway: scores asr output against the carbon test set. See README.md.
# Usage: score.py <test set dir> <hyp dir> <clean dir> [results.md]
import json
import re
import sys
import unicodedata
import wave
from collections import defaultdict
from pathlib import Path

import jiwer
import numpy as np
from num2words import num2words

RATE = 16000
ENGINES = ["st", "v3", "ultra"]
ENGINE_NAMES = {"st": "SpeechTranscriber", "v3": "Parakeet v3", "ultra": "Parakeet Ultra"}
FILLERS = {
    "en": {"uh", "um", "umm", "hmm", "hm", "mm", "mmm", "mhm", "mm-hmm", "uh-huh", "eh", "ah", "er", "erm", "huh"},
    "fr": {"euh", "heu", "hum", "hmm", "hm", "mh", "mhm", "mm", "mmh", "bah", "ah", "oh", "eh", "hein"},
}
SPELLINGS = {"ok": "okay", "alright": "all right", "gonna": "going to"}
MIN_MUTE = 1.0  # a run of digital zeros at least this long counts as a muted stretch
EDGE = 0.5  # a phantom word lies wholly inside the run, this far from both edges (not a real word's timing spill)

root, hyp_dir, clean_dir = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
out_path = Path(sys.argv[4]) if len(sys.argv) > 4 else Path(__file__).parent / "results.md"
meetings = {m["id"]: m for m in json.loads((root / "index.json").read_text())["meetings"]}


def spell_number(token, lang):
    try:
        value = float(token) if "." in token else int(token)
        return num2words(value, lang=lang)
    except (ValueError, OverflowError):
        return token


def normalize_word(word, lang):
    """One written word → its scoring tokens (lowercase, no punctuation, numbers spelled, fillers dropped)."""
    if re.fullmatch(r"SPEAKER_\d+|<NA>|[+*@]", word):
        return []
    if lang == "en" and re.fullmatch(r"(anti-)?([A-Z]_)+('?s)?", word):  # AMI letter acronyms: T_V_s → tvs
        word = word.replace("_", "")
    word = unicodedata.normalize("NFC", word).lower().replace("’", "'")
    word = word.replace("_", " ")
    word = re.sub(r"(\d),(\d{3})", r"\1\2", word)
    word = re.sub(r"(\d),(\d)", r"\1.\2", word)
    word = word.replace("%", " percent" if lang == "en" else " pour cent")
    word = re.sub(r"[€$]([\d.]+)", lambda m: m.group(1) + (" euros" if word.startswith("€") else " dollars"), word)
    word = word.replace("€", " euros ").replace("$", " dollars ")
    if lang == "fr":
        word = re.sub(r"\b(qu|[cdjlmnst]|jusqu|lorsqu|puisqu|quelqu)'", r"\1' ", word)
    word = re.sub(r"(\d+(\.\d+)?)", lambda m: " " + spell_number(m.group(1), lang) + " ", word)
    word = re.sub(r"[^\w' ]+", " ", word.replace("-", " "))
    if lang == "fr":
        word = word.replace("'", "' ")
    else:
        word = re.sub(r"(?<!\w)'|'(?!\w)", " ", word)
    tokens = " ".join(SPELLINGS.get(t, t) for t in word.split()).split()
    return [t for t in tokens if t and t not in FILLERS[lang] and t != "'"]


def tokens_with_times(words, lang):
    tokens = []
    for w in words:
        for t in normalize_word(w["w"], lang):
            tokens.append((t, w.get("s"), w.get("e"), w.get("speaker")))
    return tokens


def reference(meeting_id, stream):
    d = root / "meetings" / meeting_id / "reference"
    if stream == "mix":
        words = []
        for block in (d / "transcript.srt").read_text().strip().split("\n\n"):
            lines = block.splitlines()
            stamps = re.findall(r"(\d+):(\d+):(\d+)[,.](\d+)", lines[1])
            start, end = [int(h) * 3600 + int(m) * 60 + int(sec) + int(ms) / 1000 for h, m, sec, ms in stamps[:2]]
            for w in " ".join(lines[2:]).split():
                words.append({"w": w, "s": start, "e": end})
        return words
    rows = [json.loads(l) for l in (d / "words.jsonl").read_text().splitlines() if l.strip()]
    return [{"w": r["word"], "s": r["start"], "e": r["end"], "speaker": r["speaker"]} for r in rows if r["stream"] == stream]


def muted_mask(wav_path):
    with wave.open(str(wav_path)) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    zero = x == 0
    edges = np.flatnonzero(np.diff(np.concatenate(([0], zero.astype(np.int8), [0]))))
    runs = [(s / RATE, e / RATE) for s, e in zip(edges[::2], edges[1::2]) if (e - s) >= MIN_MUTE * RATE]
    return runs, len(x) / RATE


def in_runs(start, end, runs):
    lo, hi = 0, len(runs)
    while lo < hi:
        mid = (lo + hi) // 2
        if runs[mid][1] <= start:
            lo = mid + 1
        else:
            hi = mid
    return lo < len(runs) and runs[lo][0] + EDGE <= start and end <= runs[lo][1] - EDGE


def speaker_turns(meeting_id, speakers):
    turns = []
    for line in (root / "meetings" / meeting_id / "reference" / "timeline.rttm").read_text().splitlines():
        f = line.split()
        if f and f[7] in speakers:
            turns.append((float(f[3]), float(f[3]) + float(f[4]), f[7]))
    return turns


def oracle_speaker(start, end, turns):
    """The reference Speaker whose turn overlaps the word most, else the nearest turn within 1 s."""
    best, best_overlap, nearest, nearest_gap = None, 0.0, None, 1.0
    for s, e, spk in turns:
        overlap = min(end, e) - max(start, s)
        if overlap > best_overlap:
            best, best_overlap = spk, overlap
        gap = max(s - end, start - e)
        if gap < nearest_gap:
            nearest, nearest_gap = spk, gap
    return best or nearest


def group_of(meeting_id, stream):
    corpus = meeting_id.split("-")[0]
    return {"ami": "EN AMI", "icsi": "EN ICSI", "summre": "FR SUMM-RE", "simsamu": "FR phone (Simsamu)"}.get(corpus, corpus), stream


stats = defaultdict(lambda: defaultdict(float))
per_file = []
timing = defaultdict(list)
attribution = defaultdict(lambda: [0, 0])
phantom = defaultdict(lambda: [0, 0.0])
phantom_examples = defaultdict(list)
cost = defaultdict(list)
silence_rows = []

for engine in ENGINES:
    for path in sorted((hyp_dir / engine).glob("*.json")):
        meeting_id, stream = path.stem.split("__")
        hyp = json.loads(path.read_text())
        if meeting_id == "silence":
            text = " ".join(w["w"] for w in hyp["words"])
            silence_rows.append((stream, engine, hyp["model"], len(hyp["words"]), text[:80]))
            continue
        lang = meetings[meeting_id]["language"]
        cost[engine].append(hyp)
        ref_tokens = tokens_with_times(reference(meeting_id, stream), lang)
        hyp_tokens = tokens_with_times(hyp["words"], lang)
        ref_text = " ".join(t[0] for t in ref_tokens)
        hyp_text = " ".join(t[0] for t in hyp_tokens)
        result = jiwer.process_words(ref_text, hyp_text)
        group = group_of(meeting_id, stream)
        s = stats[(group, engine)]
        s["ref"] += len(ref_tokens)
        s["sub"] += result.substitutions
        s["del"] += result.deletions
        s["ins"] += result.insertions
        per_file.append((meeting_id, stream, engine, len(ref_tokens), result.wer))

        if stream == "mix":
            continue
        runs, duration = muted_mask(clean_dir / meeting_id / f"{stream}.wav")
        muted_seconds = sum(e - s for s, e in runs)
        ghosts = [t for t in hyp_tokens if t[1] is not None and in_runs(t[1], t[2], runs)]
        phantom[(lang, stream, engine)][0] += len(ghosts)
        phantom[(lang, stream, engine)][1] += muted_seconds
        if ghosts and len(phantom_examples[engine]) < 6:
            phantom_examples[engine].append(f"{meeting_id} {stream}: " + " ".join(f"{t[0]}@{t[1]:.1f}" for t in ghosts[:6]))

        speakers = set(meetings[meeting_id]["them"]) if stream == "them" else {meetings[meeting_id]["me"]}
        turns = speaker_turns(meeting_id, speakers)
        for chunk in result.alignments[0]:
            if chunk.type != "equal":
                continue
            for i in range(chunk.ref_end_idx - chunk.ref_start_idx):
                r = ref_tokens[chunk.ref_start_idx + i]
                h = hyp_tokens[chunk.hyp_start_idx + i]
                if None in (r[1], r[2], h[1], h[2]):
                    continue
                timing[(lang, engine)].append((h[1] - r[1], h[2] - r[2]))
                if stream == "them" and len(speakers) > 1:
                    a = attribution[(lang, engine)]
                    a[0] += oracle_speaker(h[1], h[2], turns) == r[3]
                    a[1] += 1


def pct(x):
    return f"{100 * x:.1f} %"


lines = ["# Transcription eval results", "", f"Generated by `score.py` from `{hyp_dir}`.", ""]
lines += ["## WER per corpus and stream", "",
          "Corpus-level WER (total edits / total reference words) after the shared normalizer. Substitutions / deletions / insertions in brackets.", "",
          "| Corpus | Stream | Ref words | " + " | ".join(ENGINE_NAMES[e] for e in ENGINES) + " |",
          "|---|---|---:|" + "---:|" * len(ENGINES)]
for group in sorted({g for g, _ in stats}):
    ref = stats[(group, ENGINES[0])]["ref"] or stats[(group, ENGINES[-1])]["ref"]
    cells = []
    for engine in ENGINES:
        s = stats.get((group, engine))
        if not s:
            cells.append("–")
            continue
        wer = (s["sub"] + s["del"] + s["ins"]) / s["ref"]
        cells.append(f"**{pct(wer)}** ({pct(s['sub'] / s['ref'])} / {pct(s['del'] / s['ref'])} / {pct(s['ins'] / s['ref'])})")
    lines.append(f"| {group[0]} | {group[1]} | {int(ref)} | " + " | ".join(cells) + " |")

lines += ["", "## Language totals", "", "| Language | " + " | ".join(ENGINE_NAMES[e] for e in ENGINES) + " |", "|---|" + "---:|" * len(ENGINES)]
for label, prefix in (("English (AMI + ICSI, Me + Them)", "EN"), ("French (SUMM-RE Me + Them, Simsamu)", "FR")):
    cells = []
    for engine in ENGINES:
        rows = [s for (g, e), s in stats.items() if e == engine and g[0].startswith(prefix)]
        ref = sum(s["ref"] for s in rows)
        cells.append(pct(sum(s["sub"] + s["del"] + s["ins"] for s in rows) / ref) if ref else "–")
    lines.append(f"| {label} | " + " | ".join(cells) + " |")

lines += ["", "## Phantom text on muted stretches", "",
          f"Words lying wholly inside a run of digital zeros ≥ {MIN_MUTE:.0f} s, at least {EDGE} s from both edges, in the clean track (the other stream's solo turns, muted by `prep.py`), per hour of muted audio.", "",
          "| Language | Stream | Muted hours | " + " | ".join(ENGINE_NAMES[e] for e in ENGINES) + " |", "|---|---|---:|" + "---:|" * len(ENGINES)]
for lang, stream in sorted({(l, s) for l, s, _ in phantom}):
    hours = phantom[(lang, stream, ENGINES[0])][1] / 3600 or phantom[(lang, stream, ENGINES[-1])][1] / 3600
    cells = [f"{phantom[(lang, stream, e)][0] / max(hours, 1e-9):.1f}" for e in ENGINES]
    lines.append(f"| {lang} | {stream} | {hours:.1f} | " + " | ".join(cells) + " |")
for engine in ENGINES:
    for example in phantom_examples[engine]:
        lines.append(f"- {ENGINE_NAMES[engine]}: {example}")

lines += ["", "## Silence fixtures (10 min each)", "", "| Fixture | Engine | Model | Words | Text |", "|---|---|---|---:|---|"]
for fixture, engine, model, count, text in sorted(silence_rows):
    lines.append(f"| {fixture} | {ENGINE_NAMES[engine]} | {model} | {count} | {text} |")

lines += ["", "## Word timings against the reference", "",
          "Matched words only (aligned hits), hypothesis minus reference, in seconds. Oracle attribution: each matched Them word takes the reference Speaker turn it overlaps most (nearest within 1 s), scored against its true Speaker, on Meetings with ≥ 2 Them speakers. It isolates what timing alone costs the word-level merge.", "",
          "| Language | Engine | Matched words | Start offset median | abs(start) p50 / p90 | End offset median | abs(end) p50 / p90 | Oracle attribution |",
          "|---|---|---:|---:|---:|---:|---:|---:|"]
for (lang, engine), deltas in sorted(timing.items()):
    d = np.array(deltas)
    a = attribution[(lang, engine)]
    lines.append(f"| {lang} | {ENGINE_NAMES[engine]} | {len(d)} | {np.median(d[:, 0]):+.2f} | {np.median(np.abs(d[:, 0])):.2f} / {np.percentile(np.abs(d[:, 0]), 90):.2f} | "
                 f"{np.median(d[:, 1]):+.2f} | {np.median(np.abs(d[:, 1])):.2f} / {np.percentile(np.abs(d[:, 1]), 90):.2f} | {pct(a[0] / a[1]) if a[1] else '–'} |")

lines += ["", "## Cost on this Mac", "", "Batch runs, one process per file. Peak RSS is the measuring process only: SpeechTranscriber runs in a system daemon, so its in-process number is not its real footprint.", "",
          "| Engine | Files | Audio hours | Wall seconds | × real time | Load seconds (median / max) | Peak RSS MB (median / max) |", "|---|---:|---:|---:|---:|---:|---:|"]
for engine in ENGINES:
    rows = cost[engine]
    if not rows:
        continue
    audio = sum(r["duration"] for r in rows)
    wall = sum(r["wallSeconds"] for r in rows)
    loads = [r["loadSeconds"] for r in rows]
    rss = [r["peakRSSMB"] for r in rows]
    lines.append(f"| {ENGINE_NAMES[engine]} | {len(rows)} | {audio / 3600:.1f} | {wall:.0f} | {audio / wall:.0f}× | {np.median(loads):.1f} / {max(loads):.1f} | {np.median(rss):.0f} / {max(rss):.0f} |")

lines += ["", "## Per file", "", "| Meeting | Stream | Ref words | " + " | ".join(ENGINE_NAMES[e] for e in ENGINES) + " |", "|---|---|---:|" + "---:|" * len(ENGINES)]
table = defaultdict(dict)
refs = {}
for meeting_id, stream, engine, n, wer in per_file:
    table[(meeting_id, stream)][engine] = wer
    refs[(meeting_id, stream)] = n
for key in sorted(table):
    lines.append(f"| {key[0]} | {key[1]} | {refs[key]} | " + " | ".join(pct(table[key][e]) if e in table[key] else "–" for e in ENGINES) + " |")

out_path.write_text("\n".join(lines) + "\n")
print("\n".join(lines[:60]))

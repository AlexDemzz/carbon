# PROTOTYPE, throwaway: the mixed-language check (open question 2).
#   build: <out>/mixed/mix.wav + reference.json, ~10 min alternating English (AMI ES2004a/b, ES2011a, Me) and
#     French (SUMM-RE 021a, Me) solo utterances of 3-15 s, 0.6 s apart: a meeting where people
#     switch language turn by turn.
#   score: per engine, WER on the English and the French turns, and how often each turn's output
#     comes out in the other language (or empty).
#   langs: on the French corpus runs, the share of output phrases (split at 1 s pauses) that read
#     as English, i.e. Parakeet's auto language slipping.
# Usage: mixed.py build <test set dir> <clean dir> | mixed.py score <test set dir> <clean dir> <hyp dir>
#        | mixed.py langs <test set dir> <hyp dir>
import json
import sys
import wave
from pathlib import Path

import numpy as np

RATE = 16000
GAP = 0.6
SOURCES = {"en": ["ami-ES2004a", "ami-ES2004b", "ami-ES2011a"], "fr": ["summre-021a_EARD", "summre-032a_EARH", "summre-018a_EARZ"]}
STOP = {
    "en": set("the and you that is it to of we what this have was with for but they not are be so i think yeah okay".split()),
    "fr": set("le la les et est que qui de des un une je on pas ce ça c'est en du pour mais oui nous vous il elle dans".split()),
}


def read(path):
    with wave.open(str(path)) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)


def language_of(text):
    words = [w.strip(".,?!;:").lower() for w in text.split()]
    en = sum(w in STOP["en"] for w in words)
    fr = sum(w in STOP["fr"] for w in words)
    if en == fr:
        return None
    return "en" if en > fr else "fr"


def build(root, clean):
    utterances = {"en": [], "fr": []}
    for lang, meeting_ids in SOURCES.items():
        for meeting_id in meeting_ids:
            m = json.loads((root / "meetings" / meeting_id / "meeting.json").read_text())
            audio = read(clean / meeting_id / "me.wav")
            segments = [json.loads(l) for l in (root / "meetings" / meeting_id / "reference" / "segments.jsonl").read_text().splitlines()]
            others = [(s["start"], s["end"]) for s in segments if s["speaker"] != m["me"]]
            for s in segments:
                if s["stream"] != "me" or not 3 <= s["end"] - s["start"] <= 15:
                    continue
                if sum(max(0, min(b, s["end"]) - max(a, s["start"])) for a, b in others) > 0.5:
                    continue
                utterances[lang].append((s, audio[int(s["start"] * RATE):int(s["end"] * RATE)]))
    pieces, turns, t = [], [], 0.0
    gap = np.zeros(int(GAP * RATE), dtype=np.int16)
    for i in range(min(len(utterances["en"]), len(utterances["fr"]))):
        for lang in ("en", "fr"):
            segment, audio = utterances[lang][i]
            turns.append({"lang": lang, "start": t, "end": t + len(audio) / RATE, "text": segment["text"]})
            pieces += [audio, gap]
            t += (len(audio) + len(gap)) / RATE
        if t > 600:
            break
    out = clean / "mixed"
    out.mkdir(parents=True, exist_ok=True)
    with wave.open(str(out / "mix.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(np.concatenate(pieces).tobytes())
    (out / "reference.json").write_text(json.dumps(turns, ensure_ascii=False, indent=1))
    print(f"{len(turns)} turns, {t:.0f} s")


def score(root, clean, hyp_dir):
    sys.argv = ["score.py", str(root), str(hyp_dir), str(clean), "/dev/null"]
    import jiwer
    scorer = {}
    exec((Path(__file__).parent / "score.py").read_text().split("stats = defaultdict")[0], scorer)
    turns = json.loads((clean / "mixed" / "reference.json").read_text())
    print("| Engine | Model | EN turns WER | FR turns WER | EN turns out in French / empty | FR turns out in English / empty |")
    print("|---|---|---:|---:|---:|---:|")
    for path in sorted(hyp_dir.glob("*/mixed__*.json")):
        hyp = json.loads(path.read_text())
        row = {}
        for lang in ("en", "fr"):
            ref_text, hyp_text, wrong, empty, n = [], [], 0, 0, 0
            for turn in (t for t in turns if t["lang"] == lang):
                words = [w["w"] for w in hyp["words"] if turn["start"] - 0.3 <= (w["s"] + w["e"]) / 2 < turn["end"] + 0.3]
                ref_text += [x for w in turn["text"].split() for x in scorer["normalize_word"](w, lang)]
                hyp_text += [x for w in words for x in scorer["normalize_word"](w, lang)]
                n += 1
                if not words:
                    empty += 1
                elif language_of(" ".join(words)) not in (lang, None):
                    wrong += 1
            row[lang] = (jiwer.wer(" ".join(ref_text), " ".join(hyp_text)), wrong / n, empty / n)
        print(f"| {path.parent.name} | {hyp['model']} | {100 * row['en'][0]:.1f} % | {100 * row['fr'][0]:.1f} % | "
              f"{100 * row['en'][1]:.0f} % / {100 * row['en'][2]:.0f} % | {100 * row['fr'][1]:.0f} % / {100 * row['fr'][2]:.0f} % |")


def langs(root, hyp_dir):
    print("| Engine | French files | Phrases | Read as English | Examples |")
    print("|---|---:|---:|---:|---|")
    for engine_dir in sorted(p for p in hyp_dir.iterdir() if p.is_dir()):
        phrases, english, examples, files = 0, 0, [], 0
        for path in sorted(engine_dir.glob("*.json")):
            meeting_id = path.stem.split("__")[0]
            meta = root / "meetings" / meeting_id / "meeting.json"
            if not meta.exists() or json.loads(meta.read_text())["language"] != "fr":
                continue
            files += 1
            words = json.loads(path.read_text())["words"]
            phrase = []
            for i, w in enumerate(words):
                phrase.append(w["w"])
                if i + 1 == len(words) or words[i + 1]["s"] - w["e"] > 1.0:
                    if len(phrase) >= 3:
                        phrases += 1
                        if language_of(" ".join(phrase)) == "en":
                            english += 1
                            if len(examples) < 3:
                                examples.append(" ".join(phrase)[:60])
                    phrase = []
        print(f"| {engine_dir.name} | {files} | {phrases} | {100 * english / max(phrases, 1):.2f} % | {' / '.join(examples)} |")


command, root = sys.argv[1], Path(sys.argv[2])
if command == "build":
    build(root, Path(sys.argv[3]))
elif command == "score":
    score(root, Path(sys.argv[3]), Path(sys.argv[4]))
else:
    langs(root, Path(sys.argv[3]))

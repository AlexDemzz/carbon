# PROTOTYPE, throwaway: the proper-noun check (open question 9).
#   lists: writes names/<meeting>.txt, the person names the reference says in that Meeting, as
#     the attendee names EventKit would hand Carbon (first names only, as said in the room).
#   score: per engine and boost setting, the share of reference name mentions the transcript
#     gets right (count-matched per stream) and the extra mentions it invents.
# Usage: names.py lists <test set dir> | names.py score <test set dir> <hyp dir>...
import json
import re
import sys
from collections import Counter
from pathlib import Path

NAMES = set("""Sarah William Chiara Abigail Abbie Stephanie Krista Rex Jose Jane Roger Ching Morgan Liz Adam
Dan Frank Bob Dave Nancy Keith Srini George Robert Wolfgang Wahlster Jackendorf Andatico Abbott Haas Fey""".split())


def mentions(words):
    tokens = [re.sub(r"('s|s')$", "", w.strip(".,?!;:\"").replace("’", "'")) for w in words]
    return Counter(t.lower() for t in tokens if t in NAMES or t.capitalize() in NAMES)


def reference(root, meeting_id, stream):
    rows = [json.loads(l) for l in (root / "meetings" / meeting_id / "reference" / "words.jsonl").read_text().splitlines()]
    return [r["word"] for r in rows if r["stream"] == stream]


command, root = sys.argv[1], Path(sys.argv[2])
if command == "lists":
    Path("names").mkdir(exist_ok=True)
    for d in sorted((root / "meetings").iterdir()):
        if not (d / "reference" / "words.jsonl").exists() or json.loads((d / "meeting.json").read_text())["language"] != "en":
            continue
        said = mentions(reference(root, d.name, "me") + reference(root, d.name, "them"))
        if said:
            (Path("names") / f"{d.name}.txt").write_text("\n".join(sorted(n.capitalize() for n in said)) + "\n")
            print(d.name, dict(said))
else:
    print("| Run | Name mentions | Right | Recall | Invented |")
    print("|---|---:|---:|---:|---:|")
    for hyp_dir in map(Path, sys.argv[3:]):
        total = right = invented = 0
        for path in sorted(hyp_dir.glob("*.json")):
            meeting_id, stream = path.stem.split("__")
            if not (Path("names") / f"{meeting_id}.txt").exists():
                continue
            hyp = json.loads(path.read_text())
            text = hyp.get("boostedText") or " ".join(w["w"] for w in hyp["words"])
            ref, got = mentions(reference(root, meeting_id, stream)), mentions(text.split())
            total += sum(ref.values())
            right += sum(min(ref[n], got[n]) for n in ref)
            invented += sum(max(0, got[n] - ref[n]) for n in got)
        print(f"| {hyp_dir} | {total} | {right} | {100 * right / max(total, 1):.0f} % | {invented} |")

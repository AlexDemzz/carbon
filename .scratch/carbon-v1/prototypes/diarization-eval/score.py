# PROTOTYPE, throwaway: scores diarize output against the carbon test set. See README.md.
# Usage: score.py <test set dir> <hyp dir> [results.md]
import json
import sys
from collections import defaultdict
from itertools import combinations
from pathlib import Path

import numpy as np
from scipy.optimize import linear_sum_assignment

FRAME = 0.01
MIN_SPEECH = 10.0
PURITY = 0.6
MARGIN = 0.10

root, hyp_dir = Path(sys.argv[1]), Path(sys.argv[2])
out_path = Path(sys.argv[3]) if len(sys.argv) > 3 else Path(__file__).parent / "results.md"
meetings = {m["id"]: m for m in json.loads((root / "index.json").read_text())["meetings"]}


def read_rttm(path):
    rows = []
    for line in path.read_text().splitlines():
        f = line.split()
        if f and f[0] == "SPEAKER":
            start, dur = float(f[3]), float(f[4])
            rows.append((f[7], start, start + dur))
    return rows


def read_jsonl(path):
    return [json.loads(l) for l in path.read_text().splitlines() if l.strip()]


def to_matrix(rows, speakers, n):
    m = np.zeros((n, len(speakers)), dtype=bool)
    index = {s: i for i, s in enumerate(speakers)}
    for spk, start, end in rows:
        if spk in index:
            m[int(round(start / FRAME)):int(round(end / FRAME)), index[spk]] = True
    return m


def collar_mask(rows, speakers, n, collar):
    keep = np.ones(n, dtype=bool)
    if collar <= 0:
        return keep
    c = int(round(collar / FRAME))
    for spk, start, end in rows:
        if spk in speakers:
            for t in (start, end):
                f = int(round(t / FRAME))
                keep[max(0, f - c):f + c] = False
    return keep


def mapping(ref, hyp):
    overlap = ref.T.astype(np.int64) @ hyp.astype(np.int64)
    r, h = linear_sum_assignment(-overlap)
    return {hi: ri for ri, hi in zip(r, h) if overlap[ri, hi] > 0}


def der(ref, hyp, keep):
    ref, hyp = ref[keep], hyp[keep]
    nref, nhyp = ref.sum(1), hyp.sum(1)
    total = nref.sum()
    miss = np.maximum(nref - nhyp, 0).sum()
    fa = np.maximum(nhyp - nref, 0).sum()
    m = mapping(ref, hyp)
    correct = sum((ref[:, r] & hyp[:, h]).sum() for h, r in m.items())
    conf = np.minimum(nref, nhyp).sum() - correct
    return dict(der=(miss + fa + conf) / total, miss=miss / total, fa=fa / total, conf=conf / total)


def load_hyp(meeting_id, stream, threshold):
    p = hyp_dir / f"{meeting_id}__{stream}__t{threshold}.json"
    return json.loads(p.read_text()) if p.exists() else None


def hyp_rows(h):
    return [(s["speaker"], s["start"], s["end"]) for s in h["segments"]]


def attribute(words, hyp, hspk, m):
    """Word-level: max overlap, nearest segment within 1 s otherwise. Returns ref-mapped speaker per word."""
    n = len(hyp)
    labelled = np.flatnonzero(hyp.any(1))
    out = []
    for w in words:
        a, b = int(round(w["start"] / FRAME)), max(int(round(w["end"] / FRAME)), int(round(w["start"] / FRAME)) + 1)
        counts = hyp[a:min(b, n)].sum(0)
        if counts.any():
            k = int(counts.argmax())
        else:
            i = np.searchsorted(labelled, a)
            near = [j for j in (i - 1, i) if 0 <= j < len(labelled)]
            j = min(near, key=lambda j: abs(labelled[j] - a), default=None)
            if j is None or abs(labelled[j] - a) > 1.0 / FRAME:
                out.append(None)
                continue
            k = int(hyp[labelled[j]].argmax())
        out.append(m.get(hspk[k]))
    return out


def phrases(words, gap=0.8, cap=15.0):
    groups, cur = [], []
    for i, w in enumerate(words):
        if cur and (w["start"] - words[cur[-1]]["end"] >= gap or w["end"] - words[cur[0]]["start"] > cap):
            groups.append(cur)
            cur = []
        cur.append(i)
    if cur:
        groups.append(cur)
    return groups


def score_meeting(mid, threshold, them_stream="themclean"):
    meta = meetings[mid]
    ref_dir = root / "meetings" / mid / "reference"
    rows = read_rttm(ref_dir / "timeline.rttm")
    if meta["me"] is None:
        stream, them = "mix", sorted({r[0] for r in rows})
    else:
        stream, them = them_stream, meta["them"]
    h = load_hyp(mid, stream, threshold)
    if h is None:
        return None
    n = int(np.ceil(meta["duration_s"] / FRAME)) + 1
    hspk = sorted({s["speaker"] for s in h["segments"]})
    ref = to_matrix(rows, them, n)
    hyp = to_matrix(hyp_rows(h), hspk, n)
    res = dict(id=mid, corpus=meta["corpus"], lang=meta["language"], true_n=len(them))
    for collar in (0.25, 0.0):
        keep = collar_mask(rows, them, n, collar)
        res[f"raw_{collar}"] = der(ref, hyp, keep)
        if meta["me"]:
            me = to_matrix(rows, [meta["me"]], n)[:, 0]
            keep = keep & ~(me & ~ref.any(1))
        res[f"der_{collar}"] = der(ref, hyp, keep)
    res["hyp_n"] = sum(1 for v in h["speech_s"].values() if v >= MIN_SPEECH)
    res["hyp_n_all"] = len(h["speech_s"])
    m = {hspk[k]: them[v] for k, v in mapping(ref, hyp).items()}
    if meta["me"]:
        words = [w for w in read_jsonl(ref_dir / "words.jsonl") if w["stream"] == "them" and w["start"] is not None and w["end"] is not None]
        words.sort(key=lambda w: w["start"])
        wl = attribute(words, hyp, hspk, m)
        res["word_acc"] = np.mean([a == w["speaker"] for a, w in zip(wl, words)])
        seg_acc = []
        for g in phrases(words):
            votes = defaultdict(float)
            for i in g:
                if wl[i] is not None:
                    votes[wl[i]] += words[i]["end"] - words[i]["start"]
            pick = max(votes, key=votes.get) if votes else None
            seg_acc += [pick == words[i]["speaker"] for i in g]
        res["seg_acc"] = np.mean(seg_acc)
    res["rtf"] = meta["duration_s"] / (h["prepare_s"] + h["cluster_s"])
    return res


def prints_for(threshold):
    """(meeting, person) -> centroid, from Them clusters mapped by purity and Me tracks' largest cluster."""
    prints = {}
    for mid, meta in meetings.items():
        if meta["me"] is None:
            continue
        rows = read_rttm(root / "meetings" / mid / "reference" / "timeline.rttm")
        n = int(np.ceil(meta["duration_s"] / FRAME)) + 1
        h = load_hyp(mid, "themclean", threshold)
        if h:
            hspk = sorted({s["speaker"] for s in h["segments"]})
            ref = to_matrix(rows, meta["them"], n)
            hyp = to_matrix(hyp_rows(h), hspk, n)
            overlap = ref.T.astype(np.int64) @ hyp.astype(np.int64)
            for k, spk in enumerate(hspk):
                if spk not in h["centroids"] or h["speech_s"].get(spk, 0) < MIN_SPEECH:
                    continue
                col = overlap[:, k]
                r = int(col.argmax())
                if col.sum() and col[r] / hyp[:, k].sum() >= PURITY:
                    key = (mid, meta["them"][r])
                    # two clusters of one person: keep the bigger one
                    if key not in prints or h["speech_s"][spk] > prints[key][1]:
                        prints[key] = (np.array(h["centroids"][spk]), h["speech_s"][spk])
        h = load_hyp(mid, "me", 0.6)
        if h and h["centroids"]:
            hspk = sorted({s["speaker"] for s in h["segments"]})
            me = to_matrix(rows, [meta["me"]], n)[:, 0]
            hyp = to_matrix(hyp_rows(h), hspk, n)
            own = [(int((hyp[:, k] & me).sum()), spk) for k, spk in enumerate(hspk)
                   if spk in h["centroids"] and h["speech_s"].get(spk, 0) >= MIN_SPEECH and (hyp[:, k] & me).sum() / hyp[:, k].sum() >= PURITY]
            if own:
                spk = max(own)[1]
                prints[(mid, meta["me"])] = (np.array(h["centroids"][spk]), h["speech_s"][spk])
    return {k: v[0] for k, v in prints.items()}


def dist(a, b):
    return 1 - float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)))


def pair_stats(prints):
    same, diff, hard = [], [], []
    series = {mid: meetings[mid]["series"] for mid in meetings}
    for (m1, p1), (m2, p2) in combinations(prints, 2):
        d = dist(prints[(m1, p1)], prints[(m2, p2)])
        if p1 == p2 and m1 != m2:
            same.append(d)
        elif p1 != p2:
            diff.append(d)
            if series[m1] == series[m2] or {p1, p2} & {"057"}:
                hard.append(d)
    return np.array(same), np.array(diff), np.array(hard)


def identify(prints, t):
    by_person = defaultdict(list)
    for (mid, p) in sorted(prints):
        by_person[p].append(mid)
    gallery = {p: prints[(mids[0], p)] for p, mids in by_person.items() if len(mids) > 1}
    stats = dict(known=0, auto_ok=0, auto_wrong=0, missed=0, unknown=0, unknown_false=0)
    for (mid, p), v in prints.items():
        if p in gallery and mid == by_person[p][0]:
            continue
        ds = sorted((dist(v, g), q) for q, g in gallery.items())
        best, runner = ds[0], ds[1] if len(ds) > 1 else (2.0, None)
        auto = best[0] < t and runner[0] - best[0] >= MARGIN
        if p in gallery:
            stats["known"] += 1
            if auto and best[1] == p:
                stats["auto_ok"] += 1
            elif auto:
                stats["auto_wrong"] += 1
            else:
                stats["missed"] += 1
        else:
            stats["unknown"] += 1
            stats["unknown_false"] += int(auto)
    return stats


def pct(x):
    return f"{100 * x:.1f}"


thresholds = sorted({float(p.stem.rsplit("__t", 1)[1]) for p in hyp_dir.glob("*.json")})
lines = ["# Diarization eval results", "", "FluidAudio offline. Them track = `themclean.wav` (muted where only Me speaks, as in a tapped call); \"raw track\" = the summed-headset `them.wav` with Me bleed. Collar 0.25 s, overlap scored, Me-only frames excluded from scoring.", ""]

lines += ["## Clustering threshold sweep (mean over Meetings)", "",
          "| Threshold | Group | DER | Miss | FA | Conf | DER collar 0 | DER raw track | Count ±1 | Count exact | Count exact, raw track | Word acc | Phrase acc |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
per_threshold = {}
for t in thresholds:
    rs = [r for r in (score_meeting(mid, t) for mid in meetings) if r]
    raw = {r["id"]: r for r in (score_meeting(mid, t, "them") for mid in meetings) if r}
    for r in rs:
        r["raw_track"] = raw.get(r["id"], r)
    per_threshold[t] = rs
    groups = {"EN (AMI+ICSI)": [r for r in rs if r["lang"] == "en"],
              "FR (SUMM-RE)": [r for r in rs if r["corpus"] == "SUMM-RE"],
              "FR phone (Simsamu)": [r for r in rs if r["corpus"] == "Simsamu"]}
    for g, gr in groups.items():
        if not gr:
            continue
        mean = lambda k, sub="der": np.mean([r[k][sub] for r in gr])
        wa = [r["word_acc"] for r in gr if "word_acc" in r]
        sa = [r["seg_acc"] for r in gr if "seg_acc" in r]
        lines.append(f"| {t} | {g} | {pct(mean('der_0.25'))} | {pct(mean('der_0.25', 'miss'))} | {pct(mean('der_0.25', 'fa'))} | "
                     f"{pct(mean('der_0.25', 'conf'))} | {pct(mean('der_0.0'))} | {pct(np.mean([r['raw_track']['der_0.25']['der'] for r in gr]))} | "
                     f"{sum(abs(r['hyp_n'] - r['true_n']) <= 1 for r in gr)}/{len(gr)} | {sum(r['hyp_n'] == r['true_n'] for r in gr)}/{len(gr)} | "
                     f"{sum(r['raw_track']['hyp_n'] == r['true_n'] for r in gr)}/{len(gr)} | "
                     f"{pct(np.mean(wa)) if wa else '—'} | {pct(np.mean(sa)) if sa else '—'} |")
lines.append("")

lines += ["## Per Meeting at 0.6 (FluidAudio default)", "",
          "| Meeting | Them speakers | Clusters ≥ 10 s (all) | DER | Miss | FA | Conf | DER raw track | Word acc | Phrase acc | × real time |",
          "|---|---|---|---|---|---|---|---|---|---|---|"]
for r in per_threshold.get(0.6, []):
    d = r["der_0.25"]
    lines.append(f"| {r['id']} | {r['true_n']} | {r['hyp_n']} ({r['hyp_n_all']}) | {pct(d['der'])} | {pct(d['miss'])} | {pct(d['fa'])} | {pct(d['conf'])} | "
                 f"{pct(r['raw_track']['der_0.25']['der'])} | {pct(r['word_acc']) if 'word_acc' in r else '—'} | {pct(r['seg_acc']) if 'seg_acc' in r else '—'} | {r['rtf']:.0f} |")
lines.append("")

lines += ["## Voice Prints", ""]
for t in thresholds:
    prints = prints_for(t)
    same, diff, hard = pair_stats(prints)
    people = len({p for _, p in prints})
    lines += [f"### Clustering threshold {t}", "",
              f"{len(prints)} prints of {people} people; {len(same)} same-speaker pairs, {len(diff)} impostor pairs ({len(hard)} hard: same series, or speaker 057's other series).", "",
              "| | min | p5 | median | p95 | max |", "|---|---|---|---|---|---|"]
    for name, arr in (("same speaker", same), ("impostor", diff), ("hard impostor", hard)):
        if len(arr):
            q = np.percentile(arr, [0, 5, 50, 95, 100])
            lines.append(f"| {name} | " + " | ".join(f"{x:.3f}" for x in q) + " |")
    lines += ["", "| Cosine distance cutoff | Same pairs below | Impostor pairs below | Id: auto-match right | Id: auto-match wrong | Id: missed (→ ask/new) | Id: new people auto-matched |",
              "|---|---|---|---|---|---|---|"]
    for cut in (0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7):
        s = identify(prints, cut)
        lines.append(f"| {cut} | {pct(np.mean(same < cut))} % | {pct(np.mean(diff < cut))} % ({int((diff < cut).sum())}) | "
                     f"{s['auto_ok']}/{s['known']} | {s['auto_wrong']} | {s['missed']} | {s['unknown_false']}/{s['unknown']} |")
    lines.append("")

out_path.write_text("\n".join(lines) + "\n")
print("\n".join(lines))

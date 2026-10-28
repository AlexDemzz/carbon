# PROTOTYPE, throwaway: WER of the 60 min real-time run (hyp/live) against the fast-fed batch run
# (hyp/st) on the same first 60 min of ICSI Bmr006, per stream.
# Usage: live_score.py <test set dir> <hyp dir> <clean dir>
import json
import sys
from pathlib import Path

import jiwer

sys.argv = ["score.py", *sys.argv[1:], "/dev/null"]
scorer = {}
exec((Path(__file__).parent / "score.py").read_text().split("stats = defaultdict")[0], scorer)
hyp_dir = Path(sys.argv[2])
for stream in ("me", "them"):
    ref = [t[0] for t in scorer["tokens_with_times"](scorer["reference"]("icsi-Bmr006", stream), "en") if t[1] is not None and t[1] < 3600]
    for run in ("st", "live"):
        words = [w for w in json.loads((hyp_dir / run / f"icsi-Bmr006__{stream}.json").read_text())["words"] if w["s"] < 3600]
        hyp = [t[0] for t in scorer["tokens_with_times"](words, "en")]
        print(f"{stream} {run}: {100 * jiwer.wer(' '.join(ref), ' '.join(hyp)):.1f} % ({len(hyp)} words, {len(ref)} ref)")

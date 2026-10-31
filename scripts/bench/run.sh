#!/bin/zsh
# scripts/bench/run.sh <recording.m4a> [seconds = 150] [offset = 60]
# Replays the recording through Bench and prints the CPU of Bench (Carbon's process) and of Apple's
# localspeechrecognition daemon over the steady part of the run: from 20 s in to 15 s before the end.
# 100% is one core, as in Activity Monitor. See docs/research/transcription-cpu-cost.md.
set -e
cd "${0:A:h}"
recording=$1; seconds=${2:-150}; offset=${3:-60}
swift build -c release -j 2 > /dev/null
.build/release/Bench "$recording" "$seconds" "$offset" > .build/bench.log 2>&1 &
bench=$!
sleep 20
python3 - "$bench" $((seconds - 35)) <<'PY'
import subprocess, sys, time
bench, window = int(sys.argv[1]), float(sys.argv[2])
def cpu():
    seconds = {}
    for line in subprocess.run(["ps", "-A", "-o", "pid=,time=,comm="], capture_output=True, text=True).stdout.splitlines():
        pid, t, comm = line.split(None, 2)
        total = 0.0
        if "-" in t:
            days, t = t.split("-")
            total += int(days) * 86400
        for part in t.split(":"):
            total = total * 60 + float(part)
        seconds[int(pid)] = (total, comm.split("/")[-1])
    return seconds
before, start = cpu(), time.time()
time.sleep(window)
after, elapsed = cpu(), time.time() - start
def share(pid):
    return (after[pid][0] - before.get(pid, (0.0,))[0]) / elapsed * 100
carbon = share(bench)
apple = sum(share(pid) for pid, (_, comm) in after.items() if comm == "localspeechrecognition")
threads = len(subprocess.run(["ps", "-M", "-p", str(bench)], capture_output=True, text=True).stdout.splitlines()) - 1
print(f"Carbon {carbon:.2f}%  localspeechrecognition {apple:.2f}%  total {carbon + apple:.2f}%  threads {threads}")
PY
wait $bench
grep DONE .build/bench.log

#!/bin/zsh
# PROTOTYPE, throwaway: runs every engine on every test-set input, one process per file under a
# timeout (CoreML can stall in a long-lived process), skipping outputs that already exist.
# Usage: run.sh <test set dir> [engines...]   engines: st v3 ultra (default: all)
set -u
root=$1; shift
engines=(${@:-st v3 ultra})
bin=.build/release/asr
mkdir -p hyp logs
inputs=()
for d in $root/meetings/*; do
  id=${d:t}
  if [[ -f $d/mix.wav ]]; then inputs+=("$id mix $d/mix.wav"); else
    inputs+=("$id me clean/$id/me.wav" "$id them clean/$id/them.wav"); fi
done
for f in clean/silence/*.wav; do inputs+=("silence ${f:t:r} $f"); done
for engine in $engines; do
  for row in $inputs; do
    parts=(${=row}); id=$parts[1]; stream=$parts[2]; wav=$parts[3]
    out=hyp/$engine/${id}__$stream.json
    [[ -f $out ]] && continue
    mkdir -p hyp/$engine
    lang=$(python3 -c "import json,sys;print(json.load(open('$root/meetings/$id/meeting.json'))['language'])" 2>/dev/null || echo en)
    case $engine in
      st) locale=$([[ $lang == fr ]] && echo fr_FR || echo en_US); cmd=($bin st $locale $wav $out) ;;
      *) cmd=($bin pk $engine $wav $out) ;;
    esac
    for attempt in 1 2; do
      gtimeout 900 /usr/bin/time -l $cmd > logs/$engine-$id-$stream.log 2>&1 && break
      echo "retry $engine $id $stream" >&2
    done
    head -1 logs/$engine-$id-$stream.log
  done
done

#!/bin/zsh
# PROTOTYPE, throwaway: the side runs behind results.md "Extra runs". Usage: extras.sh
set -u
bin=.build/release/asr
root=~/Datasets/carbon-test-set
mkdir -p hyp-mixed/{st-en,st-fr,v3,ultra} hyp-fr-silence/st hyp-names/{st,v3,ultra}
# Mixed EN/FR turns (open question 2)
$bin st en_US clean/mixed/mix.wav hyp-mixed/st-en/mixed__mix.json
$bin st fr_FR clean/mixed/mix.wav hyp-mixed/st-fr/mixed__mix.json
$bin pk v3 clean/mixed/mix.wav hyp-mixed/v3/mixed__mix.json
$bin pk ultra clean/mixed/mix.wav hyp-mixed/ultra/mixed__mix.json
# Silence fixtures on the French model (open question 3)
for f in clean/silence/*.wav; do $bin st fr_FR $f hyp-fr-silence/st/silence__${f:t:r}.json; done
# Attendee-name boosting (open question 9)
for n in names/*.txt; do
  id=${n:t:r}
  for s in me them; do
    $bin st en_US clean/$id/$s.wav hyp-names/st/${id}__$s.json --context $n
    for v in v3 ultra; do gtimeout 900 $bin pk $v clean/$id/$s.wav hyp-names/$v/${id}__$s.json --vocab $n; done
  done
done
# Cold Core ML loads from a fresh copy of each model (open question 5)
for v in v3 ultra; do
  src=$(ls -d ~/Library/Application\ Support/FluidAudio/Models/parakeet-*$( [[ $v == ultra ]] && echo ultra || echo v3)* | head -1)
  dst=$TMPDIR/cold-$v-$RANDOM/${src:t}
  mkdir -p ${dst:h}; cp -R $src $dst
  du -sh $src
  $bin load $v $dst; $bin load $v $dst
  rm -rf ${dst:h}
done

#!/bin/sh
# PROTOTYPE, throwaway. Every AMI, ICSI and SUMM-RE Meeting through both variants, one at a time.
set -u
cd "$(dirname "$0")"
if [ ! -x summarize ]; then
  tmp=$(mktemp -d) && cp summarize.swift "$tmp/main.swift" && swiftc -O "$tmp/main.swift" -o summarize || exit 1
fi
for m in "${TEST_SET:-$HOME/Datasets/carbon-test-set}"/meetings/ami-* "${TEST_SET:-$HOME/Datasets/carbon-test-set}"/meetings/icsi-* "${TEST_SET:-$HOME/Datasets/carbon-test-set}"/meetings/summre-*; do
  for v in rolling mapreduce; do
    [ -f "results/$(basename "$m").$v.json" ] && continue
    ./summarize "$m" "$v" results
  done
done

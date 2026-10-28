#!/bin/zsh
# PROTOTYPE, throwaway: open question 4. Two SpeechTranscriber streams fed in real time for 60 min
# (ICSI Bmr006 Me + Them, clean tracks), as a live Meeting would, while `top` samples CPU, energy
# impact and memory of both feeders and the speech XPC service every 10 s, and `pmset` logs
# thermal state and battery. Usage: live.sh   (after prep.py; writes hyp/live/, logs/live-*.txt)
set -u
mkdir -p clean/live hyp/live logs
for s in me them; do
  [[ -f clean/live/$s.wav ]] || uv run -q --with numpy python -c "
import wave,sys
r=wave.open('clean/icsi-Bmr006/$s.wav'); p=r.getparams(); x=r.readframes(3600*16000)
w=wave.open('clean/live/$s.wav','wb'); w.setparams(p); w.writeframes(x); w.close()"
done
pmset -g batt > logs/live-pmset.txt
(while true; do date +%s; pmset -g therm | grep -E "CPU_Speed_Limit|Thermal|warning" ; sleep 60; done) >> logs/live-pmset.txt 2>&1 &
pm=$!
top -l 400 -s 10 -stats pid,command,cpu,power,mem -o cpu > logs/live-top.txt &
tp=$!
.build/release/asr st en_US clean/live/me.wav hyp/live/icsi-Bmr006__me.json --realtime > logs/live-me.log 2>&1 &
a=$!
.build/release/asr st en_US clean/live/them.wav hyp/live/icsi-Bmr006__them.json --realtime > logs/live-them.log 2>&1 &
b=$!
wait $a $b
kill $tp $pm
pmset -g batt >> logs/live-pmset.txt
cat logs/live-me.log logs/live-them.log

#!/bin/bash

raw_file="raw.txt"

grep -vE '^(#|$)' "$raw_file" > raw.tmp

grep '^www\.' raw.tmp > with_www.tmp

# comm is used here since both files are still in sorted order
comm -23 raw.tmp with_www.tmp > no_www.tmp

awk '{sub(/^www\./, ""); print}' with_www.tmp > no_www_new.tmp

awk '{print "www."$0}' no_www.tmp > with_www_new.tmp

cat no_www_new.tmp with_www_new.tmp > flipped.tmp

touch flipped_dead.tmp

cat flipped.tmp | xargs -I{} -P8 bash -c "
    if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
        echo {} >> flipped_dead.tmp
    fi
"

grep -vxFf flipped_dead.tmp flipped.tmp > flipped_alive.tmp

cat flipped_alive.tmp >> raw.tmp

sort -u raw.tmp -o "$raw_file"

#!/bin/bash

raw_file="data/raw.txt"
adblock_file="adblock.txt"

grep -vE '^(#|$)' "$raw_file" > raw.tmp

grep -vE '^(!|$)' "$adblock_file" > adblock.tmp

awk '{sub(/^www\./, ""); print}' raw.tmp > raw2.tmp

sort -u raw2.tmp -o raw3.tmp

awk '{print "||" $0 "^"}' raw3.tmp > raw.tmp

if diff -q adblock.tmp raw.tmp >/dev/null; then
   echo -e "\nNo changes. Exiting...\n"
   rm *.tmp
   exit 0
fi

num_before=$(wc -l < adblock.tmp)

cp raw.tmp adblock.tmp

num_after=$(wc -l < adblock.tmp)

echo -e "\nTotal entries before: $num_before"
echo "Total entries added: $((num_after - num_before))"
echo -e "Final entries after: $num_after\n"

echo "! Title: Jarelllama's Scam Blocklist
! Description: Blocklist for scam sites extracted from Google
! Homepage: https://github.com/jarelllama/Scam-Blocklist
! License: GNU GPLv3 (https://www.gnu.org/licenses/gpl-3.0.en.html)
! Last modified: $(date -u)
! Syntax: Adblock Plus
! Total number of entries: $num_after
" | cat - adblock.tmp > "$adblock_file"

rm *.tmp

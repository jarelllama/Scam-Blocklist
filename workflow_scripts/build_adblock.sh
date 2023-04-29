#!/bin/bash

raw_file="data/raw.txt"
adblock_file="adblock.txt"
compressed_entries="data/compressed_entries.txt"

comm -23 "$raw_file" "$compressed_entries" > raw.tmp

awk '{print "||" $0 "^"}' raw.tmp > raw2.tmp

# Sorting after converting to ABP format because adding || somehow messes up the order
sort -u raw2.tmp -o raw.tmp

grep -vE '^(!|$)' "$adblock_file" > adblock.tmp

if diff -q adblock.tmp raw.tmp >/dev/null; then
   echo -e "\nNo changes. Exiting...\n"
   rm *.tmp
   exit 0
fi

num_before=$(wc -l < adblock.tmp)

cp raw.tmp adblock.tmp

num_after=$(wc -l < adblock.tmp)

echo -e "\nTotal entries before: $num_before"
echo "Difference: $((num_after - num_before))"
echo -e "Final entries after: $num_after\n"

echo "! Title: Jarelllama's Scam Blocklist
! Description: Blocklist for scam sites automatically extracted from Google
! Homepage: https://github.com/jarelllama/Scam-Blocklist
! License: GNU GPLv3 (https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md)
! Version: $(date -u +"%m.%d.%H%M%S.%Y")
! Last modified: $(date -u)
! Expires: 4 hours
! Syntax: Adblock Plus
! Total number of entries: $num_after
" | cat - adblock.tmp > "$adblock_file"

rm *.tmp

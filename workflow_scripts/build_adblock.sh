#!/bin/bash

raw_file="data/raw.txt"
list="adblock.txt"

trap "find . -maxdepth 1 -type f -name '*.tmp' -delete" EXIT

awk '{print "||" $0 "^"}' "$raw_file" > 1.tmp
sort 1.tmp -o list.tmp

grep -vE '^!' "$list" > previous.tmp

if diff -q previous.tmp list.tmp >/dev/null; then
   echo -e "\nNo changes.\n"
   exit 0
fi

num_before=$(wc -l < previous.tmp)

num_after=$(wc -l < list.tmp)

echo -e "\nTotal entries before: $num_before"
echo "Difference: $((num_after - num_before))"
echo -e "Final entries after: $num_after\n"

echo "! Title: Jarelllama's Scam Blocklist
! Description: Blocklist for scam sites automatically retrieved from Google Search
! Homepage: https://github.com/jarelllama/Scam-Blocklist
! License: GNU GPLv3 (https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md)
! Version: $(date -u +"%m.%d.%H%M%S.%Y")
! Last modified: $(date -u)
! Expires: 4 hours
! Syntax: Adblock Plus
! Total number of entries: $num_after
!" | cat - list.tmp > "$list"

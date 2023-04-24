#!/bin/bash

raw_file="raw.txt"
adblock_file="adblock.txt"

grep -vE '^(!|$)' "$raw_file" > tmp1.txt

awk '{sub(/^www\./, ""); print}' tmp1.txt > tmp2.txt

sort -u tmp2.txt -o tmp3.txt

grep -vE '^(#|$)' "$adblock_file" > tmp_adblock.txt

awk '{sub(/^\|\|/, ""); sub(/\^$/, ""); print}' tmp_adblock.txt > tmp_domains.txt

comm -23 tmp3.txt tmp_domains.txt > tmp_unique.txt

awk '{print "||" $0 "^"}' tmp_unique.txt > tmp_adblock_pending.txt

cat tmp_adblock_pending.txt >> tmp_adblock.txt

sort tmp_adblock.txt -o tmp_adblock2.txt

num_entries=$(wc -l < tmp_adblock2.txt)

echo "! Title: Jarelllama's Scam Blocklist
! Description: Blocklist for scam sites extracted from Google
! Homepage: https://github.com/jarelllama/Scam-Blocklist
! License: GNU GPLv3 (https://www.gnu.org/licenses/gpl-3.0.en.html)
! Last modified: $(date -u)
! Syntax: Adblock Plus
! Total number of entries: $num_entries
" | cat - tmp_adblock2.txt > "$adblock_file"

rm tmp*.txt

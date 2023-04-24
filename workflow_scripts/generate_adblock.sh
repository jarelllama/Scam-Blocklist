#!/bin/bash

raw_file="raw.txt"
adblock_file="adblock.txt"

grep -vE '^(#|$)' "$raw_file" > tmp1.txt

awk '{sub(/^www\./, ""); print}' tmp1.txt > tmp2.txt

sort -u tmp2.txt -o tmp3.txt

awk '{print "||" $0 "^"}' tmp3.txt > tmp4.txt

num_entries=$(wc -l < tmp4.txt)

echo "# Title: Jarelllama's Scam Blocklist
# Description: Blocklist for scam sites extracted from Google
# Homepage: https://github.com/jarelllama/Scam-Blocklist
# License: GNU GPLv3 (https://www.gnu.org/licenses/gpl-3.0.en.html)
# Last modified: $(date -u)
# Syntax: Adblock Plus
# Total number of entries: $num_entries
" | cat - tmp4.txt > "$adblock_file"

rm tmp*.txt

git config user.email "$github_email"
git config user.name "$github_name"

git add "$adblock_file"
git commit -qm "Update adblock list"
git push -q

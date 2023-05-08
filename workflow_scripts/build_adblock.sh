#!/bin/bash

raw_file="data/raw.txt"
adblock_file="adblock.txt"
subdomains_file="data/subdomains.txt"
compressed_entries_file="data/compressed_entries.txt"

while read -r subdomain; do
    grep "^${subdomain}\." "$raw_file" >> subdomains.tmp
done < "$subdomains_file"

# Remove subdomains
comm -23 "$raw_file" subdomains.tmp > 1.tmp

awk '{print "||" $0 "^"}' 1.tmp > 2.tmp

# Appending || somehow messes up the order
sort -u 2.tmp -o 2.tmp

# Remove redundant entries
comm -23 2.tmp "$compressed_entries_file" > raw.tmp

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

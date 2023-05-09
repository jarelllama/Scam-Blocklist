#!/bin/bash

raw_file="data/raw.txt"
adblock_file="adblock.txt"
subdomains_file="data/subdomains.txt"
compressed_entries_file="data/compressed_entries.txt"

comm -23 "$raw_file" "$compressed_entries_file" > raw.tmp

while read -r subdomain; do
    grep "^${subdomain}\." raw.tmp >> only_subdomains.tmp
done < "$subdomains_file"

comm -23 raw.tmp only_subdomains.tmp > second_level_domains.tmp

# I've tried using xarg parallelization here to no success
while read -r entry; do
    grep "\.${entry}$" second_level_domains.tmp > redundant.tmp
    if ! [[ -s redundant.tmp ]]; then
        continue
    fi
    echo -e "\nEntries made redundant by '${entry}':"
    cat redundant.tmp
    cat redundant.tmp >> "$compressed_entries_file"
done < second_level_domains.tmp

# The output has a high chance of having duplicates
sort -u "$compressed_entries_file" -o "$compressed_entries_file"

# Remove redundant entries
comm -23 second_level_domains.tmp "$compressed_entries_file" > 1.tmp

awk '{print "||" $0 "^"}' 1.tmp > 2.tmp

# Appending || somehow messes up the order
sort -u 2.tmp -o adblock.tmp

grep -vE '^(!|$)' "$adblock_file" > previous_adblock.tmp

if diff -q previous_adblock.tmp adblock.tmp >/dev/null; then
   echo -e "\nNo changes.\n"
   rm ./*.tmp
   exit 0
fi

num_before=$(wc -l < previous_adblock.tmp)

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

rm ./*.tmp

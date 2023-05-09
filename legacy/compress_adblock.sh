#!/bin/bash

adblock_file="adblock.txt"
compressed_entries_file="data/compressed_entries.txt"

grep -vE '^(!|$)' "$adblock_file" > adblock.tmp

echo -e "\nRedundant entries (if any):"

# I've tried using xarg parallelization here to no success
while read -r entry; do
    grep "\.${entry#||}$" adblock.tmp | awk -v entry="$entry" '{print $0 " made redundant by " entry}'  
    grep "\.${entry#||}$" adblock.tmp >> compressed_entries.tmp
done < adblock.tmp

if ! [[ -s compressed_entries.tmp ]]; then
    echo -e "\nNo redundant entries found.\n"
    rm *.tmp
    exit 0
fi

cat compressed_entries.tmp >> "$compressed_entries_file"

# The output has a high chance of having duplicates
sort -u "$compressed_entries_file" -o "$compressed_entries_file"

echo -e "\nTotal entries removed: $(wc -l < compressed_entries.tmp)\n"

rm *.tmp

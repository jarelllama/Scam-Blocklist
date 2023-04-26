#!/bin/bash

adblock_file="adblock.txt"
redundant_rules="data/redundant_rules.txt"

grep -vE '^(!|$)' "$adblock_file" > adblock.tmp

while read -r entry; do
    grep "\.${entry#||}$" adblock.tmp >> "$redundant_rules"
done < adblock.tmp

# The output has a high chance of having duplicates
sort -u "$redundant_rules" -o "$redundant_rules"

rm *.tmp

if ! [[ -s "$redundant_rules" ]]; then
    echo -e "\nNo redundant rules found.\n"
fi

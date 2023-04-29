#!/bin/bash

adblock_file="adblock.txt"
compressed_entries="data/compressed_entries.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

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

cat compressed_entries.tmp >> "$compressed_entries"

# The output has a high chance of having duplicates
sort -u "$compressed_entries" -o "$compressed_entries"

rm *.tmp

echo ""

git config user.email "$github_email"
git config user.name "$github_name"

git add "$compressed_entries"
git commit -qm "Compress Adblock entries"
git push -q

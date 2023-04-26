#!/bin/bash

adblock_file="adblock.txt"
redundant_entries="data/redundant_entries.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

touch "$redundant_entries"

grep -vE '^(!|$)' "$adblock_file" > adblock.tmp

while read -r entry; do
    grep "\.${entry#||}$" adblock.tmp >> "$redundant_entries"
done < adblock.tmp

# The output has a high chance of having duplicates
sort -u "$redundant_entries" -o "$redundant_entries"

rm *.tmp

if ! [[ -s "$redundant_entries" ]]; then
    echo -e "\nNo redundant rules found.\n"
    exit 0
fi

git config user.email "$github_email"
git config user.name "$github_name"

git add "$redundant_entries"
git commit -qm "Compress $adblock_file"
git push -q

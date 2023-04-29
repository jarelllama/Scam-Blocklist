#!/bin/bash

adblock_file="adblock.txt"
redundant_rules="data/redundant_rules.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

grep -vE '^(!|$)' "$adblock_file" > adblock.tmp

echo -e "\nRedundant rules (if any):"

# I've tried using xarg parallelization here to no success
while read -r entry; do
    grep "\.${entry#||}$" adblock.tmp | awk -v entry="$entry" '{print $0 " made redundant by " entry}'  
    grep "\.${entry#||}$" adblock.tmp >> redundant_rules.tmp
done < adblock.tmp

if ! [[ -s redundant_rules.tmp ]]; then
    echo -e "\nNo redundant rules found.\n"
    rm *.tmp
    exit 0
fi

cat redundant_rules.tmp >> "$redundant_rules"

# The output has a high chance of having duplicates
sort -u "$redundant_rules" -o "$redundant_rules"

rm *.tmp

echo ""

git config user.email "$github_email"
git config user.name "$github_name"

git add "$redundant_rules"
git commit -qm "Compress Adblock rules"
git push -q

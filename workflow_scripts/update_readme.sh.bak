#!/bin/bash

readme="README.md"
template="data/README.md.template"
domains_file="domains.txt"
adblock_file="adblock.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

adblock_count=$(grep -vE '^(!|$)' "$adblock_file" | wc -l)

domains_count=$(grep -vE '^(#|$)' "$domains_file" | wc -l)

sed -i 's/adblock_count/'"$adblock_count"'/g' "$template"

sed -i 's/domains_count/'"$domains_count"'/g' "$template"

sed -i 's/update_time/'"$(date -u +"%a %b %d %H:%M UTC")"'/g' "$template"

top_tlds=$(awk -F '.' '{print $NF}' data/raw.txt | sort | uniq -c | sort -nr | head -15 | awk '{print "| " $2, " | "$1 " |"}')

awk -v var="$top_tlds" '{gsub(/top_tlds/,var)}1' "$template" > "readme"

cp "$template" "$readme"

git config user.email "$github_email"
git config user.name "$github_name"

git add "$readme"
git commit -m "Update README"
git push

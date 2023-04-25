#!/bin/bash

readme="README.md"
template="data/README.md.template"

adblock_count=$(grep -vE '^(!|$)' "$adblock_file" | wc -l)

domains_count=$(grep -vE '^(#|$)' "$domains_file" | wc -l)

sed -i 's/adblock_count/'"$adblock_count"'/g' "$template"

sed -i 's/domains_count/'"$domains_count"'/g' "$template"

sed -i 's/update_time/'"$(date -u +"%a %b %d %H:%m UTC")"'/g' "$template"

cp "$template" "$readme"

git config user.email "$github_email"
git config user.name "$github_name"

git add "$readme"
git commit -qm "Update README"
git push -q

#!/bin/bash

readme="README.md"
template="data/README.md.template"
domains_file="domains.txt"
adblock_file="adblock.txt"

adblock_count=$(grep -vE '^(!|$)' "$adblock_file" | wc -l)

domains_count=$(grep -vE '^(#|$)' "$domains_file" | wc -l)

sed -i 's/adblock_count/'"$adblock_count"'/g' "$template"

sed -i 's/domains_count/'"$domains_count"'/g' "$template"

sed -i 's/update_time/'"$(date -u)"'/g' "$template"

cp "$template" "$readme"

# Note that only the README file should be pushed

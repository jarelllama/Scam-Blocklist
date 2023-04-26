#!/bin/bash

readme="README.md"
template="data/README.md"
raw_file="data/raw.txt"
adblock_file="adblock.txt"

adblock_count=$(grep -vE '^(!|$)' "$adblock_file" | wc -l)

domains_count=$(wc -l < "$raw_file")

sed -i 's/adblock_count/'"$adblock_count"'/g' "$template"

sed -i 's/domains_count/'"$domains_count"'/g' "$template"

if diff -q "$readme" "$template" >/dev/null; then
   echo -e "\nNo changes. Exiting...\n"
   exit 0
fi

sed -i 's/update_time/'"$(date -u +"%a %b %d %H:%M UTC")"'/g' "$template"

top_tlds=$(awk -F '.' '{print $NF}' "$raw_file" | sort | uniq -c | sort -nr | head -10 | awk '{print "| " $2, " | "$1 " |"}')

awk -v var="$top_tlds" '{gsub(/top_tlds/,var)}1' "$template" > "$readme"

# Note that only the readme file should be pushed

#!/bin/bash

readme="README.md"
domains_file="domains.txt"
adblock_file="adblock.txt"

line_num=$(cat "$readme" | grep -xn "| Syntax | Domains/Entries |" | cut -d ":" -f 1)

adblock_line=$((line_num + 2))

domains_line=$((line_num + 3))

sed -i "${adblock_line}s/.*/ /" "$readme"

sed -i "${domains_line}s/.*/ /" "$readme"

grep -vE '^(!|$)' "$adblock_file" > adblock.tmp

grep -vE '^(#|$)' "$domains_file" > domains.tmp

adblock_num=$(wc -l < adblock.tmp)

domains_num=$(wc -l < domains.tmp)

new_adblock_line="| [Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/adblock.txt) | $adblock_num |"

new_domains_line="| [Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/domains.txt) | $domains_num |"

awk -v line="$adblock_line" -v text="$new_adblock_line" 'NR==line {$0=text} {print}' "$readme" > "$readme"

awk -v line="$domains_line" -v text="$new_domains_line" 'NR==line {$0=text} {print}' "$readme" > "$readme"

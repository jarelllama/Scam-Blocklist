#!/bin/bash

readme="README.md"
domains_file="domains.txt"
adblock_file="adblock.txt"

adblock_line_num=$(cat README.md | grep -n "| \[Adblock Plus\](https://raw" | cut -d ":" -f 1)

domains_line_num=$(cat README.md | grep -n "| \[Domains\](https://raw" | cut -d ":" -f 1)

adblock_count=$(grep -vE '^(!|$)' "$adblock_file" | wc -l)

domains_count=$(grep -vE '^(#|$)' "$domains_file" | wc -l)

sed -i "${adblock_line_num}s/[0-9]\{4,\}/$adblock_count/" "$readme"

sed -i "${domains_line_num}s/[0-9]\{4,\}/$domains_count/" "$readme"

rm *.tmp

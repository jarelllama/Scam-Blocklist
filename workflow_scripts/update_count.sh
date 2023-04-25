#!/bin/bash

readme="README.md"
domains_file="domains.txt"
adblock_file="adblock.txt"

adblock_line_num=$(cat README.md | grep -n '| \[Adblock Plus\](https://raw' | cut -d ":" -f 1)

domains_line_num=$(cat README.md | grep -n '| \[Domains\](https://raw' | cut -d ":" -f 1)

grep -vE '^(!|$)' "$adblock_file" > adblock.tmp

grep -vE '^(#|$)' "$domains_file" > domains.tmp

adblock_count=$(wc -l < adblock.tmp)

domains_count=$(wc -l < domains.tmp)

sed -i "${adblock_line_num}s/[1-9]\{3,\}/$adblock_count/" "$readme"

sed -i "${domains_line_num}s/[1-9]\{3,\}/$domains_count/" "$readme"

#!/bin/bash

raw_file="raw.txt"
domains_file="domains.txt"

grep -vE '^(#|$)' "$raw_file" > raw.tmp

grep -vE '^(#|$)' "$domains_file" > domains.tmp

if diff -q domains.tmp raw.tmp >/dev/null; then
   echo -e "\nNo changes. Exiting...\n"
   rm *.tmp
   exit 0
fi

num_before=$(wc -l < domains.tmp)

cp raw.tmp domains.tmp

num_after=$(wc -l < domains.tmp)

echo -e "\nTotal domains before: $num_before"
echo "Total domains added: $((num_after - num_before))"
echo -e "Final domains after: $num_after\n"

echo "# Title: Jarelllama's Scam Blocklist
# Description: Blocklist for scam sites extracted from Google
# Homepage: https://github.com/jarelllama/Scam-Blocklist
# License: GNU GPLv3 (https://www.gnu.org/licenses/gpl-3.0.en.html)
# Last modified: $(date -u)
# Syntax: Domains
# Total number of domains: $num_after
" | cat - domains.tmp > "$domains_file"

rm *.tmp

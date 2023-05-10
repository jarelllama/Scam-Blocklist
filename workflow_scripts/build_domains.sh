#!/bin/bash

raw_file="data/raw.txt"
domains_file="domains.txt"

grep -vE '^(#|$)' "$domains_file" > previous_domains.tmp

if diff -q previous_domains.tmp "$raw_file" >/dev/null; then
   echo -e "\nNo changes.\n"
   rm ./*.tmp
   exit 0
fi

num_before=$(wc -l < previous_domains.tmp)

cp "$raw_file" domains.tmp

num_after=$(wc -l < domains.tmp)

echo -e "\nTotal domains before: $num_before"
echo "Difference: $((num_after - num_before))"
echo -e "Final domains after: $num_after\n"

echo "# Title: Jarelllama's Scam Blocklist
# Description: Blocklist for scam sites automatically extracted from Google
# Homepage: https://github.com/jarelllama/Scam-Blocklist
# License: GNU GPLv3 (https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md)
# Version: $(date -u +"%m.%d.%H%M%S.%Y")
# Last modified: $(date -u)
# Expires: 4 hours
# Syntax: Domains
# Total number of domains: $num_after
" | cat - domains.tmp > "$domains_file"

rm ./*.tmp

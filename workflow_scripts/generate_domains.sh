#!/bin/bash

raw_file="raw.txt"
domains_file="domains.txt"

grep -vE '^(#|$)' "$raw_file" > raw.tmp

grep -vE '^(#|$)' "$domains_file" > domains.tmp

if diff -q domains.tmp raw.tmp >/dev/null ; then
   echo -e "\nNo changes. Exiting...\n"
   rm *.tmp
   exit 0
fi

diff -u domains.tmp raw.tmp | patch domains.tmp

echo "# Title: Jarelllama's Scam Blocklist
# Description: Blocklist for scam sites extracted from Google
# Homepage: https://github.com/jarelllama/Scam-Blocklist
# License: GNU GPLv3 (https://www.gnu.org/licenses/gpl-3.0.en.html)
# Last modified: $(date -u)
# Syntax: Domains
# Total number of domains: $(wc -l < domains.tmp)
" | cat - domains.tmp > "$domains_file"

rm *.tmp

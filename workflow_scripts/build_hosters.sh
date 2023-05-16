#!/bin/bash

raw_file="data/optimised_entries.txt"
path="lists/hosters.txt"
comment='#'

trap "find . -maxdepth 1 -type f -name '*.tmp' -delete" EXIT

echo -e "\nBuilding Malicious Hosters..."

touch "$path"

cp "$raw_file" "${path}.tmp"

sort "${path}.tmp" -o "${path}.tmp"

grep -vE "^${comment}" "$path" > previous.tmp

if diff -q previous.tmp "${path}.tmp" >/dev/null; then
   echo "No changes."
   exit 0
fi

num_before=$(wc -l < previous.tmp)

num_after=$(wc -l < "${path}.tmp")

echo "Total entries before: $num_before"
echo "Difference: $((num_after - num_before))"
echo -e "Final entries after: $num_after\n"

echo "${comment} Title: Jarelllama's Malicious Hosters Blocklist
${comment} Description: Blocklist for malicious hosters automatically retrieved from Google Search
${comment} Homepage: https://github.com/jarelllama/Scam-Blocklist
${comment} License: GNU GPLv3 (https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md)
${comment} Version: $(date -u +"%m.%d.%H%M%S.%Y")
${comment} Last modified: $(date -u)
${comment} Expires: 4 hours
${comment} Syntax: Wildcard Domains
${comment} Total number of entries: $num_after
${comment}" | cat - "${path}.tmp" > "$path"

git add "$path"
git commit -qm "Build Malicious Hosters"

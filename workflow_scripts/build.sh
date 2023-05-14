#!/bin/bash

raw_file="data/raw.txt"
syntax="$1"
path="$2"
before="$3"
after="$4"
comment="$5"

trap "find . -maxdepth 1 -type f -name '*.tmp' -delete" EXIT

awk -v before="$before" -v after="$after" '{print before $0 after}' "$raw_file" > "${path}.tmp"

sort "${path}.tmp" -o "${path}.tmp"

if [[ "$syntax" == 'Unbound' ]]; then
    sed -i '1s/^/server:\n/' "${path}.tmp"
fi

grep -vE "^${comment}" "$path" > previous.tmp

if diff -q previous.tmp "${path}.tmp" >/dev/null; then
   echo -e "\nNo changes.\n"
   exit 0
fi

num_before=$(wc -l < previous.tmp)

num_after=$(wc -l < "${path}.tmp")

echo -e "\nTotal entries before: $num_before"
echo "Difference: $((num_after - num_before))"
echo -e "Final entries after: $num_after\n"

echo "${comment} Title: Jarelllama's Scam Blocklist
${comment} Description: Blocklist for scam sites automatically retrieved from Google Search
${comment} Homepage: https://github.com/jarelllama/Scam-Blocklist
${comment} License: GNU GPLv3 (https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md)
${comment} Version: $(date -u +"%m.%d.%H%M%S.%Y")
${comment} Last modified: $(date -u)
${comment} Expires: 4 hours
${comment} Syntax: $syntax
${comment} Total number of entries: $num_after
${comment}" | cat - "${path}.tmp" > "$path"

git add "$path"
git commit -m "Build ${syntax}"

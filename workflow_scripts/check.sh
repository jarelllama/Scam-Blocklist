#!/bin/bash

raw_file="raw.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

error=0

grep -vE '^(#|$)' "$raw_file" > 1.tmp

if grep -q '^[[:space:]]*$' 1.tmp; then
    echo -e "\nThe blocklist contains empty lines."
    error=1
fi

awk NF 1.tmp > 2.tmp

if grep -q '[A-Z]' 2.tmp; then
    echo -e "\nThe blocklist contains capitalized letters:"
    grep '[A-Z]' 2.tmp | awk '{print $0 " (case)"}'
    error=1
fi

tr '[:upper:]' '[:lower:]' < 2.tmp > 3.tmp

num_before=$(wc -l < 3.tmp)

echo -e "\nEntries removed (if any):"

awk 'seen[$0]++ == 1 {print $0 " (duplicate)"}' 3.tmp

sort -u 3.tmp -o 3.tmp

grep -E '\.(edu|gov)$' 3.tmp | awk '{print $0 " (TLD)"}'

grep -vE '\.(edu|gov)$' 3.tmp > 4.tmp

grep -vE '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' 4.tmp | awk '{print $0 " (invalid)"}'
    
grep -E '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' 4.tmp > 5.tmp

mv 5.tmp "$raw_file"

num_after=$(wc -l < "$raw_file")

if [[ "$num_before" -eq "$num_after" ]]; then
    echo -e "\nNo entries removed.\n"
else
    echo -e "\nTotal entries removed: $((num_before - num_after))\n"
    error=1
fi

rm *.tmp

if [[ "$error" -eq 0 ]]; then
    exit 0
fi

git config user.email "$github_email"
git config user.name "$github_name"

git add "$raw_file"
git commit -qm "Remove invalid entries from raw.txt"
git push -q

exit 1

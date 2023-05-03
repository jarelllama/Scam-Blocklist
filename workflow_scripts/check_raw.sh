#!/bin/bash

raw_file="data/raw.txt"
github_email='91372088+jarelllama@users.noreply.github.com'
github_name='jarelllama'

git config user.email "$github_email"
git config user.name "$github_name"

error=0

if grep -q '^[[:space:]]*$' "$raw_file"; then
    echo -e "\nThe blocklist contains empty lines."
    error=1
fi
awk NF "$raw_file" > 1.tmp

if grep -q '[A-Z]' 1.tmp; then
    echo -e "\nThe blocklist contains capitalized letters:"
    grep '[A-Z]' 1.tmp | awk '{print $0 " (case)"}'
    error=1
fi
tr '[:upper:]' '[:lower:]' < 1.tmp > 2.tmp

num_before=$(wc -l < 2.tmp)

echo -e "\nEntries removed (if any):"

awk 'seen[$0]++ == 1 {print $0 " (duplicate)"}' 2.tmp
sort -u 2.tmp -o 2.tmp

grep -E '\.(gov|edu)(\.[a-z]{2})?$' 2.tmp | awk '{print $0 " (TLD)"}'
grep -vE '\.(gov|edu)(\.[a-z]{2})?$' 2.tmp > 3.tmp

grep -vE '^[[:alnum:].-]+\.[[:alnum:]-]{2,}$' 3.tmp | awk '{print $0 " (invalid)"}'
grep -E '^[[:alnum:].-]+\.[[:alnum:]-]{2,}$' 3.tmp > 4.tmp

mv 4.tmp "$raw_file"

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

git add "$raw_file"
git commit -qm "Remove invalid entries"
git push -q

exit 1

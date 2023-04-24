#!/bin/bash

raw_file="raw.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

grep -vE '^(#|$)' "$raw_file" > tmp1.txt

echo "# Raw file for list generation
# Not to be used as a blocklist
" | cat - tmp1.txt > "$raw_file"

rm tmp*.txt

git config user.email "$github_email"
git config user.name "$github_name"

git add "$raw_file"
git commit -m "Add header to $raw_file"
git push

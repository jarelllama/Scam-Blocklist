#!/bin/bash

raw_file="data/raw.txt"

grep -vE '^(#|$)' "$raw_file" > tmp1.txt

echo "# Raw file for list generation
# Not to be used as a blocklist
" | cat - tmp1.txt > "$raw_file"

rm tmp*.txt

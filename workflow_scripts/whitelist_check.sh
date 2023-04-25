#!/bin/bash

raw_file="data/raw.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"

grep -vE '^(#|$)' "$raw_file" > raw.tmp

grep -Ff "$whitelist_file" raw.tmp | grep -vxFf "$blacklist_file" > whitelisted.tmp

if ! [[ -s whitelisted.tmp ]]; then
    echo -e "\nNo whitelisted domains found.\n"
    rm *.tmp
    exit 0
fi

echo -e "\nWhitelisted domains:"
cat whitelisted.tmp
echo ""

rm *.tmp

exit 1

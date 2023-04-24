#!/bin/bash

domains_file="domains"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"

grep -vE '^(#|$)' "$domains_file" > tmp1.txt

grep -Ff "$whitelist_file" tmp1.txt | grep -vxFf "$blacklist_file" > tmp_whitelisted.txt

if ! [[ -s tmp_whitelisted.txt ]]; then
    echo -e "\nNo whitelisted domains found\n"
    rm tmp*.txt
    exit 0
fi

echo -e "\nWhitelisted domains:"
cat tmp_whitelisted.txt
echo ""

rm tmp*.txt

exit 1

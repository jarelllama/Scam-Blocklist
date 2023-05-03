#!/bin/bash

raw_file="data/raw.txt"
blacklist_file="blacklist.txt"
toplist_file="data/toplist.txt"
subdomains_toplist_file="data/subdomains_toplist.txt"

wget -q https://raw.githubusercontent.com/hagezi/dns-data-collection/main/top/toplist.txt -O "$toplist_file"
wget -q https://raw.githubusercontent.com/hagezi/dns-data-collection/main/top/toplist-merged.txt -O "$subdomains_toplist_file"

sort -u "$toplist_file" -o "$toplist_file"
sort -u "$subdomains_toplist_file" -o "$subdomains_toplist_file"

comm -12 "$raw_file" "$toplist_file" | grep -vxFf "$blacklist_file" > in_toplist.tmp

if ! [[ -s in_toplist.tmp ]]; then
    echo -e "\nNo domains found in the toplist. Exiting without error...\n"
    rm *.tmp
    exit 0
fi

echo -e "\nDomains in the toplist:"
cat in_toplist.tmp
echo

rm *.tmp

exit 1

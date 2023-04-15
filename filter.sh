#!/bin/bash

# Define input and output file locations
input_file="pending_domains.txt"
output_file="filtered_domains.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="toplist.txt"

echo "Domains removed:"

# Remove empty lines and duplicates
awk '!a[$0]++ && NF' "$input_file" > "tmp1.txt"

# Find and print out duplicated domains
awk 'NF && seen[$0]++ == 1 { print $0, "(duplicate)" }' "$input_file"

# Remove whitelisted domains
awk -v FS=" " 'FNR==NR{a[tolower($1)]++; next} !a[tolower($1)]' "$whitelist_file" "tmp1.txt" | grep -vf "$whitelist_file" -i | awk -v FS=" " '{print $1}' > "tmp2.txt"

# Print whitelisted domains
grep -f "$whitelist_file" -i "tmp1.txt" | awk '{print $1" (whitelisted)"}'

# Sort the list alphabetically and save to the output_file
sort -o "$output_file" "tmp2.txt"

# Remove temporary files
rm tmp*.txt

# Compare with toplist domains
echo "Domains in toplist:"
comm -12 <(sort "$output_file") <(sort "$toplist_file") | grep -vFxf "$blacklist_file"

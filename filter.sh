#!/bin/bash

# Define input and output file locations
input_file="pending_domains.txt"
output_file="filtered_domains.txt"
whitelist_file="whitelist.txt"

echo "Domains removed:"

# Remove empty lines and duplicates
awk '!a[$0]++ && NF' "$input_file" > "tmp1.txt"

# Find and print out duplicated domains
awk 'seen[$0]++ == 1 { print $0 , "(duplicate)" }' "$input_file"

# Remove whitelisted domains
awk -v FS=" " 'FNR==NR{a[tolower($1)]++; next} !a[tolower($1)]' "$whitelist_file" "tmp1.txt" | grep -vf "$whitelist_file" -i | awk -v FS=" " '{print $1}' > "tmp2.txt"

# Print whitelisted domains
grep -f "$whitelist_file" -i "tmp1.txt" | awk '{print $1" (whitelisted)"}'

# Move the temporary file to the desired output file
mv "tmp2.txt" "$output_file"


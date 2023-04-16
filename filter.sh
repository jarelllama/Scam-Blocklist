#!/bin/bash

# Define input and output file locations
input_file="pending_domains.txt"
output_file="domains.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="toplist.txt"

# Backup the output file before making any changes
rsync -a "$output_file" "$output_file.bak"

# Append the input file to the output file
dd if="$input_file$ of="$output_file" conv=notrunc oflag=append

# Print out the domains removed in this run
echo "Domains removed:"

# Print out duplicated domains while skipping empty lines
awk 'NF && seen[$0]++ == 1 { print $0, "(duplicate)" }' "$input_file"

# Remove empty lines and duplicates
awk '!a[$0]++ && NF' "$input_file" > "tmp1.txt"

# Print whitelisted domains
grep -f "$whitelist_file" -i "tmp1.txt" | awk '{print $1" (whitelisted)"}'

# Remove whitelisted domains
awk -v FS=" " 'FNR==NR{a[tolower($1)]++; next} !a[tolower($1)]' "$whitelist_file" "tmp1.txt" | grep -vf "$whitelist_file" -i | awk -v FS=" " '{print $1}' > "tmp2.txt"

# Save changes to the output file and sort alphabetically
#sort --parallel=4 -m -u -o "$output_file" "tmp2.txt" "$output_file"

# Remove temporary files
rm tmp*.txt

# Compare with toplist
echo "Domains in toplist:"
comm -12 <(sort "$output_file") <(sort "$toplist_file") | grep -vFxf "$blacklist_file"

# Empty the input file
> "$input_file"

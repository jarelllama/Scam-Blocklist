#!/bin/bash

# Define input and output file locations
input_file="pending_domains.txt"
domains_file="domains.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="toplist.txt"

# Backup the domains file before making any changes
cp "$domains_file" "$domains_file.bak"

# Get the number of domains before merging
num_before=$(wc -l "$domains_file" | awk '{print $1}')

# Append the input file to the domains file
cat "$input_file" >> "$domains_file"

# Print out the domains removed in this run
echo "Domains removed:"

# Print out duplicated domains while skipping empty lines
awk '$0~/[^[:space:]]/ && seen[$0]++ == 1 { print $0, "(duplicate)" }' "$domains_file"

# Remove empty lines and duplicates
awk '$0~/[^[:space:]]/ && !a[$0]++' "$domains_file" > "tmp1.txt"

# Print whitelisted domains
grep -f "$whitelist_file" -i "tmp1.txt" | awk '{print $1" (whitelisted)"}'

# Remove whitelisted domains
awk -v FS=" " 'FNR==NR{a[tolower($1)]++; next} !a[tolower($1)]' "$whitelist_file" "tmp1.txt" | grep -vf "$whitelist_file" -i | awk -v FS=" " '{print $1}' > "tmp2.txt"

# sort alphabetically and save changes to the domains file
sort -o "$domains_file" "tmp2.txt"

# Get the number of domains after merging
num_after=$(wc -l "$domains_file" | awk '{print $1}')

# Remove temporary files
rm tmp*.txt

# Compare with toplist
echo "Domains in toplist:"
comm -12 <(sort "$domains_file") <(sort "$toplist_file") | grep -vFxf "$blacklist_file"

# Print the change in the number of domains
if [[ $num_after > $num_before ]]; then
  echo "Change in total number of unique domains: +$((num_after - num_before))"
elif [[ $num_after < $num_before ]]; then
  echo "Change in total number of unique domains: -$((num_before - num_after))"
else
  echo "Change in total number of unique domains: 0"
fi

#!/bin/bash

# Define input and output file locations
input_file="pending_domains.txt"
domains_file="domains.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="toplist.txt"

# Backup the domains file before making any changes
cp "$domains_file" "$domains_file.bak"

# Get the number of domains before merging. Does not count empty lines
num_before=$(wc -l < "$domains_file")

# Append unique entries from the input file to the domains file
# Since most domains retrieved are duplicates, this step improves performance by not including them for the filtering below
comm -23 <(sort "$input_file") <(sort "$domains_file") >> "$domains_file"

# Print out the domains removed in this run
echo "Domains removed:"

# Print out duplicated domains while skipping empty lines
# awk '$0~/[^[:space:]]/ && seen[$0]++ == 1 { print $0, "(duplicate)" }' "$domains_file"

# Remove empty lines and duplicates
awk '$0~/[^[:space:]]/ && !a[$0]++' "$domains_file" > tmp1.txt

# Remove non domain entries
awk '{ if ($0 ~ /^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$/) print $0 > tmp1.txt; else print $0" (invalid)" }' "$pending_file"

# Print whitelisted domains
# TODO: optimize
grep -f "$whitelist_file" -i tmp1.txt | awk '{print $1" (whitelisted)"}'

# Remove whitelisted domains
awk -v FS=" " 'FNR==NR{a[tolower($1)]++; next} !a[tolower($1)]' "$whitelist_file" tmp1.txt | grep -vf "$whitelist_file" -i | awk -v FS=" " '{print $1}' > tmp2.txt

# sort alphabetically and save changes to the domains file
sort -o "$domains_file" tmp2.txt

# Get the number of domains after merging
num_after=$(wc -l < "$domains_file")

# Remove temporary files
rm tmp*.txt

# Compare domains file with toplist
echo "Domains in toplist:"
comm -12 <(sort "$domains_file") <(sort "$toplist_file") | grep -vFxf "$blacklist_file"

# Calculate and print change in the updated domain file
diff=$((num_after - num_before))
change=$( [[ $diff -lt 0 ]] && echo "${diff}" || ( [[ $diff -gt 0 ]] && echo "+${diff}" || echo "0" ) )
echo "--------------------------------------------"
echo "Change in total number of unique domains: ${change}"

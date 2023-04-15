#!/bin/bash

# Define input and output file locations
input_file="new_domains.txt"
output_file="filtered_domains.txt"
whitelist_file="whitelist.txt"
toplist_file="toplist.txt"

echo "Domains removed: "

# Remove empty lines and duplicates
cat "$input_file" | awk '!/^$/ && !seen[$0]++' > tmp1.txt

sort "$input_file" | uniq -d | while read line; do echo "$line (duplicate)"; done

# Remove non-domain entries and print invalid domains
awk '{
  if ($1 ~ /^([a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$/ && $1 !~ /^\.[a-zA-Z]{2,}$/) {
    print tolower($1)
  } else {
    print $1 " (invalid)"
  }
}' tmp1.txt > tmp2.txt
grep "(invalid)" tmp2.txt | cut -d' ' -f1 | while read line; do echo "$line (invalid)"; done

# Remove whitelisted domains
awk 'FNR==NR{a[tolower($1)]++; next} !a[tolower($1)]' "$whitelist_file" tmp2.txt > tmp3.txt
grep -f "$whitelist_file" -i tmp2.txt | cut -d' ' -f1 | while read line; do echo "$line (whitelisted)"; done

# Sort the list alphabetically
sort tmp3.txt > "$output_file"

# Compare with toplist domains
echo "Domains in toplist:"
grep -f "$toplist_file" -iw "$output_file" | while read line; do echo "$line"; done

# Print stats
initial_count=$(wc -l < "$input_file")
total_removed_count=$(grep -c -e "(duplicate)" -e "(invalid)" -e "(whitelisted)" tmp2.txt)
final_count=$(wc -l < "$output_file")
echo "Initial number of domains: $initial_count"
echo "Total number of removed domains: $total_removed_count"
echo "Final number of domains after filtering: $final_count"

# Remove temporary files
rm tmp1.txt tmp2.txt tmp3.txt

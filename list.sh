#!/bin/bash

# Define inputs and output locations
input_file="domains.txt"
whitelist_file="whitelist.txt"
toplist_file="toplist.txt"
new_domains_file="new_domains.txt"

# Define a temporary file for storing the live domains
temp_file=$(mktemp)

# Initialize counters for the number of removed and duplicate domains
removed_domains=0
duplicate_domains=0
added_domains=0

# Add new domains to the input file if they are not already in the file
if [ -f "$new_domains_file" ]; then
  echo "Total number of new domains before filtering: $(wc -l < "$new_domains_file")"
  while read -r new_domain; do
    if grep -qFx "$new_domain" "$input_file"; then
      duplicate_domains=$((duplicate_domains+1))
    else
      echo "$new_domain" >> "$input_file"
      added_domains=$((added_domains+1))
    fi
  done < "$new_domains_file"
fi

# Loop over each line in the input file
while read -r domain; do
  # Check if the domain or any of its subdomains appear in the whitelist
  if grep -qFf "$whitelist_file" <(echo "$domain"); then
    echo "Domain removed: $domain (whitelisted)"
    removed_domains=$((removed_domains+1))
  # Check if the domain is already in the temporary file
  elif grep -qFx "$domain" "$temp_file"; then
    duplicate_domains=$((duplicate_domains+1))
    echo "Domain removed: $domain (duplicate)"
  # Check if the domain is dead
  elif dig @1.1.1.1 "$domain" | grep -q 'NXDOMAIN'; then
    echo "Domain removed: $domain (dead)"
    removed_domains=$((removed_domains+1))
  else
    echo "$domain" >> "$temp_file"
  fi
done < "$input_file"

# Copy the temporary file to the input file
cp "$temp_file" "$input_file"

# Sort the input file and overwrite it
sort -o "$input_file" "$input_file"

# Print the total number of added, removed, and duplicate domains
echo "Total number of domains removed: $removed_domains"
echo "Total number of duplicate domains: $duplicate_domains"

# Compare the input file with the toplist file and output common domains
echo "Domains in toplist:"
comm -12 <(sort "$input_file") <(sort "$toplist_file")

# Remove the temporary file
rm "$temp_file"

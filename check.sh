#!/bin/bash

# Define inputs and output locations
input_file="domains.txt"
whitelist_file="whitelist.txt"
toplist_file="toplist.txt"

# Define a temporary file for storing the live domains
temp_file=$(mktemp)

# Initialize a counter for the number of removed domains
removed_domains=0

# Loop over each line in the input file
while read -r domain; do
  # Check if the domain or any of its subdomains appear in the whitelist
  if grep -qFf "$whitelist_file" <(echo "$domain"); then
    echo "Removing whitelisted domain: $domain"
    removed_domains=$((removed_domains+1))
  # Check if the domain is dead
  elif dig @1.1.1.1 "$domain" | grep -q 'NXDOMAIN'; then
    echo "Removing dead domain: $domain"
    removed_domains=$((removed_domains+1))
  else
    # Check if the domain is already in the temporary file
    if ! grep -qFx "$domain" "$temp_file"; then
      echo "$domain" >> "$temp_file"
    fi
  fi
done < "$input_file"

# Copy the temporary file to the input file
cp "$temp_file" "$input_file"

# Sort the input file and overwrite it
sort -o "$input_file" "$input_file"

# Compare the input file with the toplist file and output common domains
echo "Domains in toplist:"
comm -12 <(sort "$input_file") <(sort "$toplist_file")

# Print the total number of removed domains
echo "Total number of removed domains: $removed_domains"

# Remove the temporary file
rm "$temp_file"

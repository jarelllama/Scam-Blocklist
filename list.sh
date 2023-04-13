#!/bin/bash

# Define the input file                              input_file="domains.txt"

# Define a temporary file for storing the live domains
temp_file=$(mktemp)

# Initialize a counter for the number of removed domains
removed_domains=0

# Loop over each line in the input file
while read -r domain; do
  # If the domain returns NXDOMAIN, remove it
  if dig @1.1.1.1 "$domain" | grep -q 'NXDOMAIN'; then
    echo "Removing dead domain: $domain"                 removed_domains=$((removed_domains+1))
  else
    # Check if the domain is already in the temporary file
    if ! grep -qFx "$domain" "$temp_file"; then
      echo "$domain" >> "$temp_file"
    fi
    echo "$domain" >> "$temp_file"
  fi
done < "$input_file"

# Copy the temporary file to the input file
cp "$temp_file" "$input_file"

# Sort the input file and overwrite it
sort "$input_file" -o "$input_file"

# Print the total number of removed domains
echo "Total number of removed domains: $removed_domains"

# Remove the temporary file
rm "$temp_file"

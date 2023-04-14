#!/bin/bash

# Define input and output file locations
input_file="new_domains.txt"
output_file="filtered_domains.txt"
whitelist_file="whitelist.txt"
toplist_file="toplist.txt"

# Remove duplicates and convert to lowercase
sort -f "$input_file" | uniq -ci | while read count domain; do
  if [[ $count -gt 1 ]]; then
    echo "$domain (duplicate)" >&2
  else
    echo "$domain"
  fi
done > "$output_file"

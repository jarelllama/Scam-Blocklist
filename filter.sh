#!/bin/bash

# Define input and output file locations
input_file="pending_domains.txt"
output_file="filtered_domains.txt"

# Use awk to remove empty lines and duplicates
awk '!a[$0]++ && NF' "$input_file" > "tmp1.txt"

# Find and print out any duplicated domains
sort "$input_file" | uniq -d | while read -r line; do printf "%s (duplicate)\n" "$line"; done

# Move the temporary file to the desired output file name
mv "tmp1.txt" "$output_file"

# Rest of the code goes here...

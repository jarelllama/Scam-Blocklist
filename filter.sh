#!/bin/bash

# Define input and output file locations
input_file="pending_domains.txt"
output_file="filtered_domains.txt"

# Remove empty lines and duplicates
awk '!a[$0]++ && NF' "$input_file" > "tmp1.txt"

# Find and print out duplicated domains
awk 'seen[$0]++ == 1 { print $0 , "(duplicate)" }' "$input_file"

# Move the temporary file to the desired output file
mv "tmp1.txt" "$output_file"


#!/bin/bash

# TODO: ensure whitelist is read in lowercase

# Define input and output file locations
input_file="new_domains.txt"
output_file="new_domains.txt"
whitelist_file="whitelist.txt"

awk '
    # Skip empty lines
    /^[[:space:]]*$/ {next}

    # Remove duplicates
    !seen[$0]++ {

        # Remove non domain entries while keeping all levels of subdomain and remove .TLD
        if ($1 ~ /^([a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$/ && $1 !~ /^\.[a-zA-Z]{2,}$/) {

            # Convert to lowercase
            $0 = tolower($0)
            print
 
        }
    }
' "$input_file" > "$input_file.tmp"

# Remove domains matching whitelist terms
comm -23 - <(sort -f "$whitelist_file") > "$input_file.tmp"

# Output the modified file
mv "$input_file.tmp" "$output_file"


# Count number of lines in original file
original_count=$(wc -l < "$new_domains_file")


# Sort final list alphabetically
sort -f "$new_domains_file" -o "$new_domains_file"

# Print removed domains and reasons
echo "Removed domains:"
awk -F. '{print tolower($1)}' "$new_domains_file" | sort | uniq -d | grep -wf - <(sort -f "$new_domains_file" "$whitelist_file" | uniq -d) | sed 's/^\([^[:space:]]*\)/\1 (duplicate)/'
grep -wif "$whitelist_file" "$new_domains_file" | sed 's/^\([^[:space:]]*\)/\1 (whitelisted)/'

# Count number of lines in final file
total_count=$(wc -l < "$new_domains_file")

# Print results
echo "Original number of domains: $original_count"
echo "Total domains removed: $(($original_count - $total_count))"
echo "Final number of domains: $total_count"

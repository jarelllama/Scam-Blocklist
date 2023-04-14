#!/bin/bash

# TODO: ensure whitelist is read in lowercase

# Define input and output file locations
input_file="new_domains.txt"
output_file="new_domains.txt"
whitelist_file="whitelist.txt"

# TODO: remove empty lines

# Convert all entries to lowercase
tr '[:upper:]' '[:lower:]' < "$input_file" > "$output_file"

# Use awk to process the input file
awk '
    # Remove duplicates
    !seen[$0]++ {

        # Remove non-domains
        if ($0 ~ /^[a-zA-Z0-9\.-]+$/) {

            # Split the domain name into its component parts
            split($0, parts, ".")

            # Remove TLDs and single level domains
            if (length(parts) > 2 || ($0 ~ /\.[a-zA-Z]{2,}$/ && length(parts) == 2 && parts[1] != "")) {
                print
            }
        }
    }
' "$input_file" > "$input_file.tmp"

# Output the modified version
mv "$input_file.tmp" $output_file"



# Count number of lines in original file
original_count=$(wc -l < "$new_domains_file")

# Remove duplicates and domains matching whitelist
#sort -uf "$new_domains_file" | comm -23 - <(sort -f "$whitelist_file") > "$new_domains_file.tmp"
#mv "$new_domains_file.tmp" "$new_domains_file"

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

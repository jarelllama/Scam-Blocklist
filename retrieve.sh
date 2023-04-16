#!/bin/bash

# Define input and output file locations
output_file="pending_domains.txt"
search_terms_file="search_terms.txt"

# Define the number of search results
num_results=120

# Define a user agent to prevent Google from blocking the search request
user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"

# Create an associative array to store only unique domains
declare -A unique_domains

# If the output file is not empty, prompt the user whether to empty it
if [[ -s "$output_file" ]]; then
    read -p "$output_file is not empty. Do you want to empty it? (Y/n): " answer
    if [[ ! "$answer" == "n" ]]; then
        > "$output_file"
    fi
fi

# Print out the search terms being used in this run
echo "Search terms:"

# Read search terms from file and loop through each term
while IFS= read -r line || [[ -n "$line" ]]; do
    # Ignore empty lines
    if [[ -n "$line" ]]; then
        # Replace non-alphanumeric characters with plus signs and group sequential plus signs into a single plus sign
        encoded_search_term=$(echo "$line" | sed -E 's/[^[:alnum:]]+/\+/g')
        
        # Use the search term to search Google with filtering off
        google_search_url="https://www.google.com/search?q=\"${encoded_search_term}\"&num=$num_results&filter=0"

        # Send the request to Google and extract all domains and subdomains from the HTML. Remove www., empty lines and duplicates
        domains=$(curl -s --max-redirs 0 -H "User-Agent: $user_agent" "$google_search_url" | grep -o '<a href="[^"]*"' | sed 's/^<a href="//' | sed 's/"$//' | awk -F/ '{print $3}' | sort -u | sed 's/^www\.//' | sed '/^$/d')

        # Count the number of domains
        if [[ -z "$domains" ]]; then
            num_domains=0
        else
            num_domains=$(echo "$domains" | wc -l)
        fi

        # Print the total number of domains for each search term
        echo "$line"
        echo "Number of unique domains found: $num_domains"
        echo "--------------------------------------------"

        # Loop through each domain and add it to associative array only if it is unique
        for domain in $domains; do
            if [[ ! ${unique_domains["$domain"]+_} ]]; then
                unique_domains["$domain"]=1
                echo "$domain" >> "$output_file"
            fi
        done
    fi
done < "$search_terms_file"

# Count unique domains and print the number of domains found
total_unique_domains=${#unique_domains[@]}
echo "Total number of unique domains found: $total_unique_domains"

# Prompt the user whether to merge the retrieved domains with the blocklist
read -p "Merge the retrieved domains with the blocklist? (Y/n): " answer
if [[ ! "$answer" == "n" ]]; then
    bash merge.sh
fi

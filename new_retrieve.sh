#!/bin/bash

# Define input and output file locations
whitelist_file="whitelist.txt"
new_domains_file="new_domains.txt"
search_terms_file="search_terms.txt"

# Define the number of search results
num_results=120

# Define a user agent to prevent Google from blocking the search request
user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"

# Create an associative array to store unique domains
declare -A unique_domains

echo "Search terms:"

# Read search terms from file and loop through each term
while IFS= read -r line || [[ -n "$line" ]]; do
    # Ignore empty lines
    if [[ -n "$line" ]]; then
        # Encode the search term for use in the Google search URL
        encoded_search_term=${line// /+}

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
        echo "---------------------------------------"

        # Add each domain to the associative array
        for domain in $domains; do
            unique_domains["$domain"]=1
        done
    fi
done < "$search_terms_file"

# Get the number of unique domains found and print it
num_unique_domains=${#unique_domains[@]}
echo "Total number of unique domains found: $num_unique_domains"

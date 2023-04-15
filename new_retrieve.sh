#!/bin/bash

# Define input and output file locations
whitelist_file="whitelist.txt"
new_domains_file="new_domains.txt"
search_terms_file="search_terms.txt"

# If new_domains_file is not empty, prompt the user whether to empty it or not.
if [ -s "$new_domains_file" ]
then
    read -p "new_domains_file is not empty. Do you want to empty it? (y/n)" answer
    if [ "$answer" == "y" ]
    then
        > $new_domains_file                              fi
fi

# Define the number of search results per page
num_results=120

# Define a user agent to prevent Google from blocking the search request
user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"

# Ask the user to input a search term
read -p "Input search term: " search_term

# Encode the search term for use in the Google search URL
encoded_search_term=${search_term// /+}

# Use the search term to search Google with filtering off and get up to 120 search results per page
google_search_url="https://www.google.com/search?q=\"${encoded_search_term}\"&num=$num_results&filter=0"

# Send the request to Google and extract all domains and subdomains from the HTML, then remove www. and empty lines
domains=$(curl -s --max-redirs 0 -H "User-Agent: $user_agent" "$google_search_url" | grep -o '<a href="[^"]*"' | sed 's/^<a href="//' | sed 's/"$//' | awk -F/ '{print $3}' | sort -u | sed 's/^www\.//' | sed '/^$/d')

# Print the domains on separate lines
echo "$domains"

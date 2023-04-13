#!/bin/bash

# Prompt the user to input a search query and store it in a variable called 'og_query'
read -p "Enter a search query: " og_query

# Format the search query for use in a Google search URL
query="\"$og_query\""
query=$(echo "$query" | sed 's/ /+/g')

# Set the user agent and number of results to retrieve
user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3"
num_results=100

# Construct the Google search URL using the formatted query and number of results
search_url="https://www.google.com/search?q=${query}&num=${num_results}&filter=0"

# Retrieve the search results page from Google, extract the URLs, and filter out irrelevant domains
# Store the resulting list of domains in a variable called 'search_results'
search_results=$(curl -s -A "$user_agent" "$search_url" | grep -o '<a href="[^"]*"' | sed 's/^<a href="//' | sed 's/"$//' | awk -F/ '{print $3}' | sort -u | sed 's/^www\.//' | grep -v -i 'scam\|google\|pinterest\|reddit\|socialgrep\|zoominfo')

# Iterate over the list of domains and check if each domain is live
# Print the live domains to the console
for domain in $search_results; do
  if dig @1.1.1.1 "$domain" | grep -q 'NXDOMAIN'; then
    # Domain is dead
    continue
  fi
  echo "$domain"
done

# Print the original search query to the console for reference
echo "Search term used: $og_query"

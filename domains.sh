#!/bin/bash

# Prompt the user to input a search query and store it in a variable called 'og_query'
read -p "Enter a search query: " og_query

# Format the search query for use in a Google search URL
# Wrap the query in double quotes to search for exact match
query="\"$og_query\""

# Replace any spaces with '+' for use in the search URL
query=${query// /+}

# Set the user agent and number of results to retrieve
user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3"
num_results=100

# Construct the Google search URL using the formatted query and number of results
search_url="https://www.google.com/search?q=${query}&num=${num_results}&filter=0"

# Retrieve the search results page from Google, extract the URLs, and filter out irrelevant domains
# Store the resulting list of domains in a variable called 'search_results'
search_results=$(curl -s -A "$user_agent" "$search_url" | grep -o '<a href="[^"]*"' | sed 's/^<a href="//' | sed 's/"$//' | awk -F/ '{print $3}' | sort -u | sed 's/^www\.//' | grep -v -i 'scam\|google\|pinterest\|reddit\|socialgrep\|zoominfo')

# Iterate over the list of domains
# Print the live domains to the console
for domain in $search_results; do
  echo "$domain"
done

# Print the original search query to the console for reference
echo "Search term used: $og_query"

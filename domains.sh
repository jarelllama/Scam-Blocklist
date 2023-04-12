#!/bin/bash

read -p "Enter a search query: " og_query

query="\"$og_query\""
query=$(echo "$query" | sed 's/ /+/g')
user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3"
num_results=100

search_url="https://www.google.com/search?q=${query}&num=${num_results}&filter=0"

search_results=$(curl -s -A "$user_agent" "$search_url" | grep -o '<a href="[^"]*"' | sed 's/^<a href="//' | sed 's/"$//' | awk -F/ '{print $3}' | sort -u | sed 's/^www\.//' | grep -v -i 'scam' | grep -v -i 'google' | grep -v -i 'pinterest' | grep -v -i 'reddit' | grep -v -i 'socialgrep' | grep -v -i 'zoominfo')

for domain in $search_results; do
    if dig +short "$domain" | grep -q '^$'; then
        continue
    fi
    echo "$domain"
done

echo "Search term used: $og_query"

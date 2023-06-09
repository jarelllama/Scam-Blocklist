#!/bin/bash

# Define input and output file locations
whitelist_file="whitelist.txt"
new_domains_file="new_domains.txt"
search_terms_file="search_terms.txt"

# Ask the user if they want to manually input a search term
read -p "Do you want to manually input a search term? (y/N) " choice

# If the user chooses to manually input a search term
if [ "$choice" == "y" ]; then
    # Ask the user to input the search term
    read -p "Enter the search term: " input_term

    # Add the input search term to the search_terms array
    search_terms=("$input_term")
else
    # Read the search terms from the search terms file and store them in an array
    IFS=$'\r\n' GLOBIGNORE='*' command eval 'search_terms=($(cat "$search_terms_file"))'
fi

# Define the function to process a search term
# Note variables apparently don't work here
function process_term() {
    # Get the search term
    og_query=$1

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
    search_results=$(curl -s -A "$user_agent" "$search_url" | grep -o '<a href="[^"]*"' | sed 's/^<a href="//' | sed 's/"$//' | awk -F/ '{print $3}' | sort -u | sed 's/^www\.//')
    
# Append the list of domains to the new domains file
    echo "$search_results" | grep -v '^$' >> "new_domains.txt"

    # Count the number of domains found for the search term
    num_domains=$(echo "$search_results" | wc -l)
    if [ -z "$search_results" ]; then
        echo "\"$og_query\": No domains found"
    else
        echo "\"$og_query\": $num_domains"
    fi

    # Print a separator between search terms
    echo "--------------------------------------------------"
}

# Export the function so that it can be called by xargs
export -f process_term

# Process each search term in parallel using xargs
printf '%s\0' "${search_terms[@]}" | xargs -0 -P "$(nproc)" -I '{}' bash -c 'process_term "$@"' _ '{}'

# Count number of lines in original file
original_count=$(wc -l < "$new_domains_file")

# Remove duplicates and domains matching whitelist
sort -uf "$new_domains_file" | comm -23 - <(sort -f "$whitelist_file") > "$new_domains_file.tmp"
mv "$new_domains_file.tmp" "$new_domains_file"

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

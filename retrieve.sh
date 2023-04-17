#!/bin/bash

# Define input and output file locations
pending_file="pending_domains.txt"
search_terms_file="search_terms.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="toplist.txt"

# Define the number of search results
num_results=120

# Define a user agent to prevent Google from blocking the search request
user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"

# Create an associative array to store unique domains
declare -A unique_domains

# If the pending domains file is not empty, prompt the user whether to empty it
if [[ -s "$pending_file" ]]; then
    read -p "$pending_file is not empty. Do you want to empty it? (Y/n): " answer
    if [[ ! "$answer" == "n" ]]; then
        > "$pending_file"
    fi
fi

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
        # Empty lines and duplicates have to be removed here for accurate counting of the retrieved domains by each search term
        domains=$(curl -s --max-redirs 0 -H "User-Agent: $user_agent" "$google_search_url" | grep -o '<a href="[^"]*"' | sed 's/^<a href="//' | sed 's/"$//' | awk -F/ '{print $3}' | sort -u | sed 's/^www\.//' | sed '/^$/d')

        # Count the number of domains retrieved by the specific search term
        if [[ -z "$domains" ]]; then
            num_domains=0
        else
            num_domains=$(echo "$domains" | wc -l)
        fi

        # Print the number of domains retrieved by the search term
        echo "$line"
        echo "Number of unique domains retrieved: $num_domains"
        echo "--------------------------------------------"

        # Loop through each domain and add it to associative array only if it is unique
        for domain in $domains; do
            if [[ ! ${unique_domains["$domain"]+_} ]]; then
                unique_domains["$domain"]=1
                # Output unique domains to the pending domains
                echo "$domain" >> "$pending_file"
            fi
        done
    fi
done < "$search_terms_file"

# Print number of unique domains retrieved in this run
total_unique_domains=${#unique_domains[@]}
echo "Total number of unique domains retrieved: $total_unique_domains"

echo "Filtering domains..."

# Count the number of pending domains before filtering
num_before=$(wc -l < "$pending_file")

echo "Domains removed:"

# Print whitelisted domains
grep -f "$whitelist_file" -i "$pending_file" | awk '{print $1" (whitelisted)"}'

# Remove whitelisted domains
awk -v FS=" " 'FNR==NR{a[tolower($1)]++; next} !a[tolower($1)]' "$whitelist_file" "$pending_file" | grep -vf "$whitelist_file" -i | awk -v FS=" " '{print $1}' > tmp1.txt

# Sort alphabetically and save changes to the pending domains file
sort -o "$pending_file" tmp1.txt

# Print pending domains found in the toplist
echo "Domains in toplist:"
comm -12 <(sort "$pending_file") <(sort "$toplist_file") | grep -vFxf "$blacklist_file"

# Remove temporary files
rm tmp*.txt

# Count the number of pending domains after filtering
num_after=$(wc -l < "$pending_file")

# Print the number of pending domains before and after filtering
echo "Pending domains after filtering: $num_before"
echo "Pending domains after filtering: $num_after"

# Calculate and print change in the updated pending domains file
diff=$((num_after - num_before))
change=$( [[ $diff -lt 0 ]] && echo "${diff}" || ( [[ $diff -gt 0 ]] && echo "+${diff}" || echo "0" ) )
echo "Change: ${change} domains"

echo "--------------------------------------------"

echo "Choose how to proceed:"
echo "1. Merge with blocklist (default)"
echo "2. Add to whitelist"
echo "3. Add to blacklist"
echo "4. Run filter again"
read choice

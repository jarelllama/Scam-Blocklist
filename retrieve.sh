#!/bin/bash

# Define input and output file locations
domains_file="domains.txt"
pending_file="pending_domains.txt"
search_terms_file="search_terms.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="toplist.txt"
tlds_file="white_tlds.txt"

# Define the number of search results
num_results=120

# Define a user agent to prevent Google from blocking the search request
user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"

# Create an associative array to store unique domains
declare -A unique_domains

# If the pending domains file is not empty, prompt the user whether to empty it
if [[ -s "$pending_file" ]]; then
    read -p "$pending_file is not empty. Do you want to empty it? (Y/n): " answer
    [[ $answer == "y" ]] && > "$pending_file"
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
        num_domains=$(echo -n "$domains" | grep -oF '.' | wc -l)

        # Print the number of domains retrieved by the search term
        echo "$line"
        echo "Unique domains retrieved: $num_domains"
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

# Count the number of unique domains retrieved in this run
total_unique_domains=${#unique_domains[@]}

# Count the number of pending domains before filtering
num_before=$(wc -l < "$pending_file")

# Sort pending domains alphabetically
sort -o "$pending_file" "$pending_file"

# Create temporary file
touch tmp1.txt

echo "Domains removed:"

# Print and remove non domain entries
awk '{ if ($0 ~ /^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$/) print $0 > "tmp1.txt"; else print $0" (invalid)" }' "$pending_file"

# Print domains with whitelisted TLDs
grep -oE "(\S+)\.($(paste -sd '|' "$tlds_file"))$" tmp1.txt | sed "s/\(.*\)/\1 (TLD)/"

# Remove domains with whitelisted TLDs
grep -vE "\.($(paste -sd '|' "$tlds_file"))$" tmp1.txt > tmp2.txt

# Print whitelisted domains
grep -f "$whitelist_file" -i tmp2.txt | awk '{print $1" (whitelisted)"}'

# Remove whitelisted domains
awk -v FS=" " 'FNR==NR{a[tolower($1)]++; next} !a[tolower($1)]' "$whitelist_file" tmp2.txt | grep -vf "$whitelist_file" -i | awk -v FS=" " '{print $1}' > tmp3.txt

# Save changes to the pending domains file
mv tmp3.txt "$pending_file"

# Print domains found in the toplist
echo "Domains in toplist:"
comm -12 <(sort "$pending_file") <(sort "$toplist_file") | grep -vFxf "$blacklist_file"

# Count the number of pending domains after filtering
num_after=$(wc -l < "$pending_file")

# Remove temporary files
rm tmp*.txt

# Print counters
echo "--------------------------------------------"
echo "Total domains retrieved: $total_unique_domains"
echo "Total domains pending: $num_before"
echo "Total domains removed: $((num_before - num_after))"
echo "Final domains pending: $num_after"
echo "--------------------------------------------"

echo "Choose how to proceed:"
echo "1. Merge with blocklist (default)"
echo "2. Add to whitelist"
echo "3. Add to blacklist"
echo "4. Run filter again"
echo "5. Exit"
read choice

case "$choice" in
    1)
        echo "Merge with blocklist"

        # Backup the domains file before making any changes
        cp "$domains_file" "$domains_file.bak"

        # Count the number of domains before merging
        num_before=$(wc -l < "$domains_file")

        # Append unique pending domains to the domains file
        comm -23 "$pending_file" "$domains_file" >> "$domains_file"

        # Sort domains file alphabetically
        sort -o "$domains_file" "$domains_file"

        # Count the number of domains after merging
        num_after=$(wc -l < "$domains_file")

        # Print counters
        echo "--------------------------------------------"
        echo "Total domains before: $num_before"
        echo "Total domains added: $((num_before - num_after))"
        echo "Final domains after: $num_after"
        echo "--------------------------------------------"
        ;;
    2)
        echo "Add to whitelist"
        read -p "Enter the new entry: " new_entry
        new_entry="${new_entry,,}"
        echo "$new_entry" >> "$whitelist_file"
        sort -o "$whitelist_file" "$whitelist_file"
        ;;
    3)
        echo "Add to blacklist"
        read -p "Enter the new entry: " new_entry
        new_entry="${new_entry,,}"
        echo "$new_entry" >> "$blacklist_file"
        sort -o "$blacklist_file" "$blacklist_file"
        ;;
    4)
        # Code for option 3
        echo "Option 3 selected"
        ;;
    5)
        # Code for option 3
        echo "Option 3 selected"
        ;;
        *)
        if [[ -z "$choice" ]]; then
            # default action
            echo "Invalid option selected"
            echo "Please select a valid option (1-5)"
        else
            # Print the options again
            echo "Invalid option selected: $choice"
            echo "Please select a valid option (1-5)"
        fi
esac

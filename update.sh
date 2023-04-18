#!/bin/bash

domains_file="domains.txt"
pending_file="pending_domains.txt"
search_terms_file="search_terms.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="toplist.txt"
tlds_file="white_tlds.txt"

user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"

if [[ -s "$pending_file" ]]; then
    read -p "$pending_file is not empty. Do you want to empty it? (Y/n): " answer
    if [[ ! "$answer" == "n" ]]; then
        > "$pending_file"
    fi
fi

declare -A retrieved_domains

echo "Search terms:"

# Read search terms from the search terms file and loop through each term
while IFS= read -r term || [[ -n "$term" ]]; do
    # Skip empty lines
    if [[ -n "$term" ]]; then
        # Replace non-alphanumeric characters with plus signs and group sequential plus signs into a single plus sign
        encoded_search_term=$(echo "$term" | sed -E 's/[^[:alnum:]]+/\+/g')

        google_search_url="https://www.google.com/search?q=\"${encoded_search_term}\"&num=100&filter=0"

        # Search Google and extract all domains
        # Duplicates are removed here for accurate counting of the retrieved domains by each search term
        domains=$(curl -s --max-redirs 0 -H "User-Agent: $user_agent" "$google_search_url" | grep -oE '<a href="https:\S+"' | awk -F/ '{print $3}' | sort -u)

        # Count the number of domains retrieved by the specific search term
        num_domains=$(echo -n "$domains" | grep -oF '.' | wc -l)

        echo "$term"
        echo "Unique domains retrieved: $num_domains"
        echo "--------------------------------------------"

        # Loop through each domain and add it to the associative array only if it is unique
        for domain in $domains; do
            if [[ ! ${retrieved_domains["$domain"]+_} ]]; then
                retrieved_domains["$domain"]=1

                echo "$domain" >> "$pending_file"
            fi
        done
    fi
done < "$search_terms_file"

num_retrieved=${#retrieved_domains[@]}

function filter_pending {
    cp "$pending_file" "$pending_file.bak"

    awk NF "$pending_file" > tmp1.txt

    tr '[:upper:]' '[:lower:]' < tmp1.txt > tmp2.txt

    # Removing www subdomains has to be done before sorting alphabetically
    sed -i 's/^www\.//' tmp2.txt

    # Although the retrieved domains are already deduplicated, not emptying the pending domains file may result in duplicates
    sort -uo "pending_file" tmp2.txt

    # Keep only pending domains not already in the blocklist for filtering
    # This removes the majority of pending domains and makes the further filtering more efficient
    comm -23 "$pending_file" "$domains_file" > tmp1.txt

    echo "Domains removed:"

    # Print whitelisted domains
    grep -f "$whitelist_file" tmp1.txt | awk '{print $1" (whitelisted)"}'

    # Remove whitelisted domains
    awk -v FS=" " 'FNR==NR{a[tolower($1)]++; next} !a[tolower($1)]' "$whitelist_file" tmp1.txt | grep -vf "$whitelist_file" -i | awk -v FS=" " '{print $1}' > tmp2.txt

    # Print and remove non domain entries
    # Non domains are already be filtered when the domains were retrieved. This code is more for debugging
    awk '{ if ($0 ~ /^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$/) print $0 > "tmp3.txt"; else print $0" (invalid)" }' tmp2.txt

    # Print domains with whitelisted TLDs
    grep -oE "(\S+)\.($(paste -sd '|' "$tlds_file"))$" tmp3.txt | sed "s/\(.*\)/\1 (TLD)/"

    # Remove domains with whitelisted TLDs
    grep -vE "\.($(paste -sd '|' "$tlds_file"))$" tmp3.txt > tmp4.txt

    # Create temporary file for dead domains and www subdomains
    touch tmp_dead.txt
    touch tmp_www.txt

    # Find and print dead domains
    cat tmp4.txt | xargs -I{} -P4 bash -c "
        if dig @1.1.1.1 {} | grep -q 'NXDOMAIN'; then
            echo {} >> tmp_dead.txt
            echo '{} (dead)'
        fi
    "

    # Remove dead domains by removing domains found in both lists
    comm -23 tmp4.txt <(sort tmp_dead.txt) > tmp5.txt

    # Add the www subdomain to dead domains
    sed 's/^/www./' tmp_dead.txt > tmpA.txt

    # Check if the www subdomains are resolving
    cat tmpA.txt | xargs -I{} -P4 bash -c "
        if ! dig @1.1.1.1 {} | grep -q 'NXDOMAIN'; then
            echo {} >> tmp_www.txt
            echo '{} is resolving'
        fi
    "

    # Append the resolving www subdomains to the pending domains file if they aren't already inside
    comm -23 <(sort tmp_www.txt) tmp5.txt >> tmp5.txt

    # Sort alphabetically after adding www subdomains
    sort -o "$pending_file" tmp5.txt
    
    # Count the number of pending domains after filtering
    num_pending=$(wc -l < "$pending_file")

    # Remove temporary files
    rm tmp*.txt

    # Print counters
    echo -e "\nTotal domains retrieved: $num_retrieved"
    echo "Domains not in blocklist: $num_pending"
    echo "Domains:"
    cat "$pending_file"
    echo -e "\nDomains in toplist:"
    grep -xFf "$pending_file" "$toplist_file" | grep -vxFf "$blacklist_file"
}

# Execute filtering for pending domains
filter_pending

# Define a function to merge filtered pending domains to the domains file
function merge_pending {
    echo "Merge with blocklist"

    # Backup the domains file before making any changes
    cp "$domains_file" "$domains_file.bak"

    # Count the number of domains before merging
    num_before=$(wc -l < "$domains_file")

    # Append unique pending domains to the domains file
    comm -23 "$pending_file" "$domains_file" >> "$domains_file"

    # Sort alphabetically
    sort -o "$domains_file" "$domains_file"

    # Count the number of domains after merging
    num_after=$(wc -l < "$domains_file")

    # Print counters
    echo "--------------------------------------------"
    echo "Total domains before: $num_before"
    echo "Total domains added: $((num_after - num_before))"
    echo "Final domains after: $num_after"

    # Empty pending domains file
    > "$pending_file"

    # Exit script
    exit 0
}

# Prompt the user with options on how to proceed
while true; do
    echo -e "\nChoose how to proceed:"
    echo "1. Merge with blocklist (default)"
    echo "2. Add to whitelist"
    echo "3. Add to blacklist"
    echo "4. Run filter again"
    echo "5. Exit"
    read choice

    case "$choice" in
        1)
            merge_pending
            ;;
        2)
            echo "Add to whitelist"
            read -p "Enter the new entry: " new_entry
            
            # Change the new entry to lowecase
            new_entry="${new_entry,,}"

            # Check if a similar term is already in the whitelist
            if grep -Fiq "$new_entry" "$whitelist_file"; then
                existing_entry=$(grep -Fi "$new_entry" "$whitelist_file" | head -n 1)
                echo "A similar term is already in the whitelist: $existing_entry"
                continue
            fi

            # Add the new entry
            echo -e "\nAdded to whitelist: $new_entry"
            echo "$new_entry" >> "$whitelist_file"

            # Remove empty lines
            awk NF "$whitelist_file" > tmp1.txt

            # Save changes and sort alphabetically
            sort -o "$whitelist_file" tmp1.txt

            # Remove temporary file
            rm tmp1.txt
            continue
            ;;
        3)
            echo "Add to blacklist"
            read -p "Enter the new entry: " new_entry
            
            # Change the new entry to lowecase
            new_entry="${new_entry,,}"
            
            # Check if the entry is valid
            if ! [[ $new_entry =~ ^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$ ]]; then
                echo -e "\nInvalid entry."
                continue
            fi

            # Check if the new entry is already in the list
            if grep -xq "$new_entry" "$blacklist_file"; then
                echo "The domain is already in the blacklist. Not added."
                continue
            fi

            # Add the new entry
            echo -e "\nAdded to blacklist: $new_entry"
            echo "$new_entry" >> "$blacklist_file"

            # Remove empty lines
            awk NF "$blacklist_file" > tmp1.txt

            # Save changes and sort alphabetically
            sort -o "$blacklist_file" tmp1.txt

            # Remove temporary file
            rm tmp1.txt
            continue
            ;;
        4)
            echo "Run filter again"
            filter_pending
            continue
            ;;
        5)
            exit 0
            ;;
        *)
            # Use domain merger as the default option
            if [[ -z "$choice" ]]; then
                merge_pending
            else
                echo "Invalid option."

                # Go back to options prompt
                continue     
            fi
    esac
done

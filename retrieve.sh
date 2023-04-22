#!/bin/bash

domains_file="domains"
pending_file="pending_domains.txt"
search_terms_file="search_terms.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="toplist.txt"

if [[ -s "$pending_file" ]]; then
    read -p "$pending_file is not empty. Do you want to empty it? (Y/n): " answer
    if [[ ! "$answer" == "n" ]]; then
        > "$pending_file"
    fi
fi

debug=0

time="y"

for arg in "$@"; do
    if [[ "$arg" == "d" ]]; then
        debug=1
    fi
    if [[ "$arg" == "w" ]]; then
        time="w"
    elif [[ "$arg" == "m" ]]; then
        time="m"
    fi
done

declare -A retrieved_domains

echo "Search terms:"

# A blank IFS ensures the entire search term is read
while IFS= read -r term; do
    # Checks if the line is non empty and not a comment
    if [[ -n "$term" ]] && [[ ! "$term" =~ ^\# ]]; then
        # gsub is used here to replace consecutive non-alphanumeric characters with a single plus sign
        encoded_term=$(echo "$term" | awk '{gsub(/[^[:alnum:]]+/,"+"); print}')

        user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"

        google_search_url="https://www.google.com/search?q=\"${encoded_term}\"&num=100&filter=0&tbs=qdr:${time}"

        # Search Google and extract all domains
        # Duplicates are removed here for accurate counting of the retrieved domains by each search term
        domains=$(curl -s --max-redirs 0 -H "User-Agent: $user_agent" "$google_search_url" | grep -oE '<a href="https:\S+"' | awk -F/ '{print $3}' | sort -u)

        echo "$term"

        if [[ "$debug" -eq 1 ]]; then
            echo "$domains"
        fi

        echo "Unique domains retrieved: $(echo "$domains" | wc -w)"
        echo "--------------------------------------------"

        # Check if each domain is already in the retrieved domains associative array
        for domain in "$domains"; do
            if [[ ${retrieved_domains["$domain"]+_} ]]; then
               continue 
            fi
            # Add the unique domain to the associative array
            retrieved_domains["$domain"]=1
            echo "$domain" >> "$pending_file"
        done
    fi
done < "$search_terms_file"

num_retrieved=${#retrieved_domains[@]}

function filter_pending {
    cp "$pending_file" "$pending_file.bak"

    awk NF "$pending_file" > tmp1.txt

    tr '[:upper:]' '[:lower:]' < tmp1.txt > tmp2.txt

    sort -u tmp2.txt -o tmp3.txt

    # This removes the majority of pending domains and makes the further filtering more efficient
    comm -23 tmp3.txt "$domains_file" > tmp4.txt

    echo "Domains removed:"

    grep -Ff "$whitelist_file" tmp4.txt | grep -vxFf "$blacklist_file" | awk '{print $0 " (whitelisted)"}'

    grep -Ff "$whitelist_file" tmp4.txt | grep -vxFf "$blacklist_file" > tmp_white.txt

    comm -23 tmp4.txt <(sort tmp_white.txt) > tmp5.txt

    grep -E '\.(edu|gov)$' tmp5.txt | awk '{print $0 " (TLD)"}'

    grep -vE '\.(edu|gov)$' tmp5.txt > tmp6.txt

    # This regex checks for valid domains
    grep -vE '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' tmp6.txt | awk '{print $0 " (invalid)"}'
    
    grep -E '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' tmp6.txt > tmp7.txt

    touch tmp_dead.txt

    # Use parallel processing
    cat tmp7.txt | xargs -I{} -P4 bash -c "
        if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> tmp_dead.txt
            echo '{} (dead)'
        fi
    "

    comm -23 tmp7.txt <(sort tmp_dead.txt) > tmp8.txt

    # This portion of code removes www subdomains for domains that have it and adds the www subdomains to those that don't. This effectively flips which domains have the www subdomain
    # This reduces the number of domains checked by the dead domains filter. Thus, improves efficiency

    grep '^www\.' tmp8.txt > tmp_with_www.txt

    comm -23 tmp8.txt <(sort tmp_with_www.txt) > tmp_no_www.txt

    awk '{sub(/^www\./, ""); print}' tmp_with_www.txt > tmp_no_www_new.txt

    awk '{print "www."$0}' tmp_no_www.txt > tmp_with_www_new.txt

    cat tmp_no_www_new.txt tmp_with_www_new.txt > tmp_flipped.txt

    touch tmp_flipped_dead.txt

    cat tmp_flipped.txt | xargs -I{} -P4 bash -c "
        if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> tmp_flipped_dead.txt
        fi
    "
    
    comm -23 <(sort tmp_flipped.txt) <(sort tmp_flipped_dead.txt) > tmp_flipped_alive.txt

    cat tmp8.txt tmp_flipped_alive.txt > tmp9.txt

    sort tmp9.txt -o "$pending_file"
    
    rm tmp*.txt

    echo -e "\nTotal domains retrieved: $num_retrieved"
    echo "Pending domains not in blocklist: $(comm -23 "$pending_file" "$domains_file" | wc -l)"
    echo "Domains:"
    cat "$pending_file"
    echo -e "\nDomains in toplist:"
    # About 8x faster than comm due to not needing to sort the toplist
    grep -xFf "$pending_file" "$toplist_file" | grep -vxFf "$blacklist_file"
}

filter_pending

function merge_pending {
    echo "Merge with blocklist"

    cp "$domains_file" "$domains_file.bak"

    num_before=$(wc -l < "$domains_file")

    cat "$pending_file" >> "$domains_file" 

    sort -u "$domains_file" -o "$domains_file"

    num_after=$(wc -l < "$domains_file")

    echo "--------------------------------------------"
    echo "Total domains before: $num_before"
    echo "Total domains added: $((num_after - num_before))"
    echo "Final domains after: $num_after"

    > "$pending_file"

    exit 0
}

function edit_whitelist {
    echo "Whitelist"

    read -p $'Enter the new entry (add \'-\' to remove entry):\n' new_entry

    # Change the new entry to lowecase
    new_entry="${new_entry,,}"

    if [[ "$new_entry" == -* ]]; then
        new_entry=$(echo "$new_entry" | cut -c 2-)
        if ! grep -xFq "$new_entry" "$2"; then
            echo -e "\nEntry not found in $1: $new_entry"
            continue
        fi
        echo -e "\nRemoved from $1: $new_entry"
        sed -i "/^$new_entry$/d" "$2"
        continue
    fi

    if [[ "$new_entry" =~ [[:space:]] ]]; then
        echo -e "\nInvalid entry. Not added."
        continue
    fi
    
    if grep -Fq "$new_entry" "$whitelist_file"; then
        # head -n is used here for when multiple whitelisted terms match the new entry
        existing_entry=$(grep -F "$new_entry" "$whitelist_file" | head -n 1)
        echo -e "\nA similar term is already in the whitelist: $existing_entry"
        continue
    fi

    echo -e "\nAdded to $1: $new_entry"
    echo "$new_entry" >> "$2"

    awk NF "$2" > tmp1.txt

    sort tmp1.txt -o "$2"

    rm tmp*.txt
}

function edit_blacklist {
    echo "Blacklist"

    read -p $'Enter the new entry (add \'-\' to remove entry):\n' new_entry
            
    remove_entry=0

    if [[ "$new_entry" == -* ]]; then
        new_entry=$(echo "$new_entry" | cut -c 2-)
        remove_entry=1
    fi

    new_entry="${new_entry,,}"

    if [[ "$new_entry" == www.* ]]; then
        www_subdomain="${new_entry}"
        new_entry=$(echo "$new_entry" | awk '{sub(/^www\./, "")}1')
    else
        www_subdomain="www.${new_entry}"
    fi

    echo "$new_entry" > tmp_entries.txt

    echo "$www_subdomain" >> tmp_entries.txt
            
    sort tmp_entries.txt -o tmp_entries.txt
            
    if [[ "$remove_entry" -eq 1 ]]; then
        if ! grep -xFqf tmp_entries.txt "$blacklist_file"; then
            echo -e "\nDomain not found in blacklist: $new_entry"
            continue
        fi

        echo -e "\nDomains removed:"
        comm -12 "$blacklist_file" tmp_entries.txt

        comm -23 "$blacklist_file" tmp_entries.txt > tmp1.txt

        mv tmp1.txt "$blacklist_file"

        rm tmp*.txt

        continue
    fi

    if ! [[ "$new_entry" =~ ^[[:alnum:].-]+\.[[:alnum:]]{2,}$ ]]; then
        echo -e "\nInvalid domain. Not added."
        continue
    fi

    touch tmp_alive_entries.txt

    while read -r entry; do
        if ! dig @1.1.1.1 "$entry" | grep -Fq 'NXDOMAIN'; then
            echo "$entry" >> tmp_alive_entries.txt
        fi
    done < tmp_entries.txt

    if ! [[ -s tmp_alive_entries.txt ]]; then
        echo -e "\nThe domain is dead. Not added."
        continue
    fi

    mv tmp_alive_entries.txt tmp_entries.txt
  
    # This checks if there are no unique entries in the new entries file
    if [[ $(comm -23 tmp_entries.txt "$blacklist_file" | wc -l) -eq 0 ]]; then
        echo -e "\nThe domain is already in the blacklist. Not added."
        continue
    fi

    echo -e "\nDomains added:"
    comm -23 tmp_entries.txt "$blacklist_file"

    cat tmp_entries.txt >> "$blacklist_file" 

    sort -u "$blacklist_file" -o "$blacklist_file"

    awk NF "$blacklist_file" > tmp1.txt

    sort tmp1.txt -o "$blacklist_file"

    rm tmp*.txt
}

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
            edit_whitelist
            continue
            ;;
        3)
            edit_blacklist
            continue
            ;;
        4)
            echo "Run filter again"
            cp "$pending_file.bak" "$pending_file"
            filter_pending
            continue
            ;;
        5)
            exit 0
            ;;
        *)
            # The z flag checks if the variable is empty
            if [[ -z "$choice" ]]; then
                merge_pending
            else
                echo "Invalid option."
                continue     
            fi
    esac
done

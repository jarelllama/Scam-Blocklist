#!/bin/bash

domains_file="domains"
pending_file="pending_domains.txt"
search_terms_file="search_terms.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="toplist.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

if [[ -s "$pending_file" ]]; then
    read -p "$pending_file is not empty. Do you want to empty it? (Y/n): " answer
    if ! [[ "$answer" == "n" ]]; then
        > "$pending_file"
    fi
fi

touch last_run.txt

# This section of code alternates between the year and month filter for Google Search
if [[ $(cat last_run.txt) == "year" ]]; then
    time="month"
    echo "month" > last_run.txt
else
    time="year"
    echo "year" > last_run.txt
fi

debug=0

for arg in "$@"; do
    if [[ "$arg" == "d" ]]; then
        debug=1
    fi
    if [[ "$arg" == "y" ]]; then
        time="year"
    elif [[ "$arg" == "m" ]]; then
        time="month"
    elif [[ "$arg" == "w" ]]; then
        time="week"
    fi
done

declare -A retrieved_domains

echo "Search filter used: $time"
echo "Search terms:"

# A blank IFS ensures the entire search term is read
while IFS= read -r term; do
    # Checks if the line is non empty and not a comment
    if ! [[ "$term" =~ ^[[:space:]]*$|^# ]]; then
        # gsub is used here to replace consecutive non-alphanumeric characters with a single plus sign
        encoded_term=$(echo "$term" | awk '{gsub(/[^[:alnum:]]+/,"+"); print}')

        user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"

        google_search_url="https://www.google.com/search?q=\"${encoded_term}\"&num=100&filter=0&tbs=qdr:${time:0:1}"

        # Search Google and extract all domains
        # Duplicates are removed here for accurate counting of the retrieved domains by each search term
        domains=$(curl -s --max-redirs 0 -H "User-Agent: $user_agent" "$google_search_url" | grep -oE '<a href="https:\S+"' | awk -F/ '{print $3}' | sort -u)

        echo "$term"

        if [[ "$debug" -eq 1 ]]; then
            echo "$domains"
        fi

        # wc -w does a better job than wc -l for counting domains in this case
        echo "Unique domains retrieved: $(echo "$domains" | wc -w)"
        echo "--------------------------------------------"

        # Check if each domain is already in the retrieved domains associative array
        # Note that quoting $domains causes errors
	for domain in $domains; do
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

    # Create a temporary copy of the domains file without the header
    grep -vE '^(#|$)' "$domains_file" > tmp_domains_file.txt

    awk NF "$pending_file" > tmp1.txt

    tr '[:upper:]' '[:lower:]' < tmp1.txt > tmp2.txt

    sort -u tmp2.txt -o tmp3.txt

    # This removes the majority of pending domains and makes the further filtering more efficient
    comm -23 tmp3.txt tmp_domains_file.txt > tmp4.txt

    echo "Domains removed:"

    grep -Ff "$whitelist_file" tmp4.txt | grep -vxFf "$blacklist_file" | awk '{print $0 " (whitelisted)"}'

    grep -Ff "$whitelist_file" tmp4.txt | grep -vxFf "$blacklist_file" > tmp_whitelisted.txt

    # Both comm and grep were tested here. It seems when only a small file needs to be sorted, the performance is generally the same
    comm -23 tmp4.txt <(sort tmp_whitelisted.txt) > tmp5.txt

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

    grep -vxFf tmp_with_www.txt tmp8.txt > tmp_no_www.txt

    awk '{sub(/^www\./, ""); print}' tmp_with_www.txt > tmp_no_www_new.txt

    awk '{print "www."$0}' tmp_no_www.txt > tmp_with_www_new.txt

    cat tmp_no_www_new.txt tmp_with_www_new.txt > tmp_flipped.txt

    touch tmp_flipped_dead.txt

    cat tmp_flipped.txt | xargs -I{} -P4 bash -c "
        if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> tmp_flipped_dead.txt
        fi
    "

    grep -vxFf tmp_flipped_dead.txt tmp_flipped.txt > tmp_flipped_alive.txt

    cat tmp8.txt tmp_flipped_alive.txt > tmp9.txt

    sort tmp9.txt -o tmp10.txt

    # Remove any new flipped domains that might already be in the blocklist
    # This is done for accurate counting
    comm -23 tmp10.txt tmp_domains_file.txt > "$pending_file"

    echo -e "\nTotal domains retrieved: $num_retrieved"
    echo "Pending domains not in blocklist: $(comm -23 "$pending_file" tmp_domains_file.txt | wc -l)"
    echo "Domains:"
    cat "$pending_file"
    echo -e "\nDomains in toplist:"
    # About 8x faster than comm due to not needing to sort the toplist
    grep -xFf "$pending_file" "$toplist_file" | grep -vxFf "$blacklist_file"
    
    rm tmp*.txt
}

filter_pending

function merge_pending {
    echo "Merge with blocklist"

    cp "$domains_file" "$domains_file.bak"

    grep -vE '^(#|$)' "$domains_file" > tmp_domains_file.txt

    num_before=$(wc -l < tmp_domains_file.txt)

    cat "$pending_file" >> tmp_domains_file.txt 

    sort -u tmp_domains_file.txt -o "$domains_file"

    num_after=$(wc -l < "$domains_file")

    echo "--------------------------------------------"
    echo "Total domains before: $num_before"
    echo "Total domains added: $((num_after - num_before))"
    echo "Final domains after: $num_after"

    > "$pending_file"

    rm tmp*.txt

    read -p "Do you want to push the updated blocklist? (y/N): " answer
    if [[ "$answer" != "y" ]]; then
        exit 0
    fi

    echo ""

    git config user.email "$github_email"
    git config user.name "$github_name"

    git add "$domains_file" "$whitelist_file" "$blacklist_file"
    git commit -m "Update domains"
    git push

    exit 0
}

function edit_whitelist {
    echo "Whitelist"

    # The $ and single quotes allow for the escape sequence
    read -p $'Enter the new entry (add \'-\' to remove entry):\n' new_entry

    new_entry="${new_entry,,}"

    if [[ "$new_entry" == -* ]]; then
        new_entry="${new_entry#-}"
        if ! grep -xFq "$new_entry" "$whitelist_file"; then
            echo -e "\nEntry not found in whitelist: $new_entry"
            return
        fi
        echo -e "\nRemoved from whitelist: $new_entry"
        sed -i "/^$new_entry$/d" "$whitelist_file"
        return
    fi

    if [[ "$new_entry" =~ [[:space:]] ]]; then
        echo -e "\nInvalid entry. Not added."
        return
    fi
    
    if grep -Fq "$new_entry" "$whitelist_file"; then
        existing_entry=$(grep -F "$new_entry" "$whitelist_file" | head -n 1)
        echo -e "\nA similar term is already in the whitelist: $existing_entry"
        return
    fi

    echo -e "\nAdded to whitelist: $new_entry"
    echo "$new_entry" >> "$whitelist_file"

    sort "$whitelist_file" -o "$whitelist_file"
}

function edit_blacklist {
    echo "Blacklist"

    read -p $'Enter the new entry (add \'-\' to remove entry):\n' new_entry
            
    remove_entry=0

    if [[ "$new_entry" == -* ]]; then
        new_entry="${new_entry#-}"
        remove_entry=1
    fi

    new_entry="${new_entry,,}"

    if [[ "$new_entry" == www.* ]]; then
        www_subdomain="${new_entry}"
        new_entry="${new_entry#www.}"
    else
        www_subdomain="www.${new_entry}"
    fi

    echo "$new_entry" > tmp_entries.txt

    echo "$www_subdomain" >> tmp_entries.txt
            
    sort tmp_entries.txt -o tmp_entries.txt
            
    if [[ "$remove_entry" -eq 1 ]]; then
        if ! grep -xFqf tmp_entries.txt "$blacklist_file"; then
            echo -e "\nDomain not found in blacklist: $new_entry"
            return
        fi

        echo -e "\nDomains removed:"
        comm -12 "$blacklist_file" tmp_entries.txt

        comm -23 "$blacklist_file" tmp_entries.txt > tmp1.txt

        mv tmp1.txt "$blacklist_file"

        rm tmp*.txt

        return
    fi

    if ! [[ "$new_entry" =~ ^[[:alnum:].-]+\.[[:alnum:]]{2,}$ ]]; then
        echo -e "\nInvalid domain. Not added."
        return
    fi

    touch tmp_alive_entries.txt

    while read -r entry; do
        if dig @1.1.1.1 "$entry" | grep -Fq 'NXDOMAIN'; then
            continue
        fi
        echo "$entry" >> tmp_alive_entries.txt
    done < tmp_entries.txt

    if ! [[ -s tmp_alive_entries.txt ]]; then
        echo -e "\nThe domain is dead. Not added."
        return
    fi

    mv tmp_alive_entries.txt tmp_entries.txt
  
    # This checks if there are no unique entries in the new entries file
    if [[ $(comm -23 tmp_entries.txt "$blacklist_file" | wc -l) -eq 0 ]]; then
        echo -e "\nThe domain is already in the blacklist. Not added."
        return
    fi

    echo -e "\nDomains added:"
    comm -23 tmp_entries.txt "$blacklist_file"

    cat tmp_entries.txt >> "$blacklist_file" 

    sort -u "$blacklist_file" -o "$blacklist_file"
    
    rm tmp*.txt
}

while true; do
    echo -e "\nChoose how to proceed:"
    echo "1. Merge with blocklist"
    echo "2. Add to whitelist"
    echo "3. Add to blacklist"
    echo "4. Run filter again"
    echo "p. Push lists changes"
    echo "x. Save pending and exit"
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
        p)
            echo "Push lists changes"

            git config user.email "$github_email"
            git config user.name "$github_name"

            git add "$whitelist_file" "$blacklist_file"
            git commit -m "Update domains"
            git push

            exit 0
            ;;
        x)
            if [[ -f tmp*.txt ]]; then
                rm tmp*.txt
            fi
            exit 0
            ;;
        *)
            echo -e "\nInvalid option."
            continue
    esac
done

#!/bin/bash

domains_file="domains"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="toplist.txt"

function remove_entry {
    # Remove the minus sign
    new_entry=$(echo "$new_entry" | cut -c 2-)

    if grep -xFq "$new_entry" "$2"; then
        echo -e "\nRemoved from $1: $new_entry"
        sed -i "/^$new_entry$/d" "$2"
    else
        echo -e "\nEntry not found in $1: $new_entry"
    fi
}

function add_entry {
    echo -e "\nAdded to $1: $new_entry"
    echo "$new_entry" >> "$2"

    awk NF "$2" > tmp1.txt
    sort tmp1.txt -o "$2" 
    rm tmp*.txt
}

while true; do
    echo -e "\nChoose which list to add to:"
    echo "1. Blocklist"
    echo "2. Whitelist"
    echo "3. Blacklist"
    echo "4. Exit"
    read choice

    case "$choice" in
        1)
            echo "Blocklist"

            read -p $'Enter the new entry (add \'-\' to remove entry):\n' new_entry
            
            remove_entry=0

            if [[ $new_entry == -* ]]; then
                new_entry=$(echo "$new_entry" | cut -c 2-)
                remove_entry=1
            fi

            new_entry="${new_entry,,}"

            new_entry=$(echo "$new_entry" | awk '{sub(/^www\./, "")}1')

            echo "$new_entry" > tmp_entries.txt

            www_subdomain="www.${new_entry}"

            echo "$www_subdomain" >> tmp_entries.txt
            
            sort tmp_entries.txt -o tmp_entries.txt
            
            if [[ "$remove_entry" -eq 1 ]]; then
                if ! grep -xFqf tmp_entries.txt "$domains_file"; then
                    echo -e "\nDomain not found in blocklist: $new_entry"
                    continue
                fi

                echo -e "\nDomains removed:"
                comm -12 "$domains_file" tmp_entries.txt

                comm -23 "$domains_file" tmp_entries.txt > tmp1.txt

                mv tmp1.txt "$domains_file"

                rm tmp*.txt

                continue
            fi

            if ! [[ $new_entry =~ ^[[:alnum:].-]+\.[[:alnum:]]{2,}$ ]]; then
                echo -e "\nInvalid domain. Not added."
                continue
            fi

            if grep -xFf tmp_entries.txt "$toplist_file" | grep -vxFqf "$blacklist_file"; then
                echo -e "\nThe domain is found in the toplist. Not added."
                echo "Matches in toplist:"
                grep -xFf tmp_entries.txt  "$toplist_file" | grep -vxFf "$blacklist_file"
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
            if [[ $(comm -23 tmp_entries.txt "$domains_file" | wc -l) -eq 0 ]]; then
                echo -e "\nThe domain is already in the blocklist. Not added."
                continue
            fi

            cp "$domains_file" "$domains_file.bak"

            echo -e "\nDomains added:"
            comm -23 tmp_entries.txt "$domains_file"

            comm -23 tmp_entries.txt "$domains_file" >> "$domains_file"

            awk NF "$domains_file" > tmp1.txt

            sort tmp1.txt -o "$domains_file"

            rm tmp*.txt
                
            continue
            ;;
        2)
            echo "Whitelist"
            list="whitelist"

            read -p $'Enter the new entry (add \'-\' to remove entry):\n' new_entry

            new_entry="${new_entry,,}"

            if [[ $new_entry == -* ]]; then
                remove_entry "$list" "$whitelist_file"
                continue
            fi

            if [[ $new_entry =~ [[:space:]] ]]; then
                echo -e "\nInvalid entry. Not added."
                continue
            fi

            if grep -Fq "$new_entry" "$whitelist_file"; then
                existing_entry=$(grep -F "$new_entry" "$whitelist_file" | head -n 1)
                echo -e "\nA similar term is already in the whitelist: $existing_entry"
                continue
            fi

            add_entry "$list" "$whitelist_file"
            
            continue
            ;;
        3)
            echo "Blacklist"
            list="blacklist"

            read -p $'Enter the new entry (add \'-\' to remove entry):\n' new_entry

            new_entry="${new_entry,,}"

            if [[ $new_entry == -* ]]; then
                remove_entry "$list" "$blacklist_file"
                continue
            fi

            if ! [[ $new_entry =~ ^[[:alnum:].-]+\.[[:alnum:]]{2,}$ ]]; then
                echo -e "\nInvalid entry. Not added."
                continue
            fi

            if grep -xFq "$new_entry" "$blacklist_file"; then
                echo -e "\nThe domain is already in the blacklist. Not added."
                continue
            fi

            add_entry "$list" "$blacklist_file"
            
            continue
            ;;
        4)
            exit 0  
            ;;
        *)
            echo -e "\nInvalid option."
            continue  
            ;;
    esac
done

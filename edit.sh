#!/bin/bash

domains_file="domains"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"

function remove_entry {
    # Remove the minus sign
    new_entry=$(echo "$new_entry" | cut -c 2-)

    if grep -xFq "$new_entry" "$2"; then
        sed -i "/^$new_entry$/d" "$2"
        echo -e "\nRemoved from $1: $new_entry"
    else
        echo -e "\nEntry not found in $1: $new_entry"
    fi
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
            list="blocklist"

            read -p $'Enter the new entry (add \'-\' to remove entry):\n' new_entry

            new_entry="${new_entry,,}"

            new_entry=$(echo "$new_entry" | awk '{sub(/^www\./, "")}1')

            if [[ $new_entry == -* ]]; then
                cp "$domains_file" "$domains_file.bak"
                remove_entry "$list" "$domains_file"
                continue
            fi

            if ! [[ $new_entry =~ ^[[:alnum:].-]+\.[[:alnum:]]{2,}$ ]]; then
                echo -e "\nInvalid entry."
                continue
            fi

            if grep -xFq "$new_entry" "$domains_file"; then
                echo -e "\nThe entry is already in the blocklist. Not added."
                continue
            fi

            if dig @1.1.1.1 "$new_entry" | grep -Fq 'NXDOMAIN'; then
                echo -e "\nThe domain is dead. Not added."
                continue
            fi

            cp "$domains_file" "$domains_file.bak"

            echo "$new_entry" >> "$domains_file"
            
            www_subdomain="www.${new_entry}"
            
            if ! dig @1.1.1.1 "$www_subdomain" | grep -Fq 'NXDOMAIN'; then
                echo "$www_subdomain" >> "$domains_file"
                echo -e "\nAdded to blocklist:\n$new_entry\n$www_subdomain"  
            else
                echo -e "\nAdded to blocklist: $new_entry"
            fi

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
                echo -e "\nInvalid entry."
                continue
            fi

            if grep -Fq "$new_entry" "$whitelist_file"; then
                existing_entry=$(grep -F "$new_entry" "$whitelist_file" | head -n 1)
                echo "A similar term is already in the whitelist: $existing_entry"
                continue
            fi

            echo -e "\nAdded to whitelist: $new_entry"
            echo "$new_entry" >> "$whitelist_file"

            awk NF "$whitelist_file" > tmp1.txt

            sort tmp1.txt -o "$whitelist_file" 

            rm tmp*.txt
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
                echo -e "\nInvalid entry."
                continue
            fi

            if grep -xFq "$new_entry" "$blacklist_file"; then
                echo "The domain is already in the blacklist. Not added."
                continue
            fi

            echo -e "\nAdded to blacklist: $new_entry"
            echo "$new_entry" >> "$blacklist_file"

            awk NF "$blacklist_file" > tmp1.txt

            sort tmp1.txt -o "$blacklist_file" 

            rm tmp*.txt
            continue
            ;;
        4)
            exit 0  
            ;;
        *)
            echo "Invalid option."
            continue  
            ;;
    esac
done

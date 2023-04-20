#!/bin/bash

domains_file="domains"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"

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

            new_entry="${new_entry,,}"

            new_entry=$(echo "$new_entry" | awk '{sub(/^www\./, "")}1')
                
            if [[ $new_entry == -* ]]; then
                new_entry=$(echo "$new_entry" | cut -c 2-)
                www_subdomain="www.${new_entry}"
                if ! grep -xFq "$new_entry" "$domains_file"; then
                    if ! grep -xFq "$www_subdomain" "$domains_file"; then
                        echo -e "\nEntry not found in blocklist: $new_entry"
                        continue 
                    fi

                    cp "$domains_file" "$domains_file.bak"

                    echo -e "\nRemoved from blocklist: $www_subdomain"

                    sed -i "/^$www_subdomain$/d" "$domains_file"

                    continue
                fi
                
                cp "$domains_file" "$domains_file.bak"
                
                sed -i "/^$new_entry$/d" "$domains_file"
                                    
                if grep -xFq "$www_subdomain" "$domains_file"; then
                    echo -e "\nRemoved from blocklist:\n$new_entry\n$www_subdomain"
                    sed -i "/^$www_subdomain$/d" "$domains_file"
                else
                    echo -e "\nRemoved from blocklist: $new_entry"
                fi
                
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

            www_subdomain="www.${new_entry}"
            www_alive=0

            if ! dig @1.1.1.1 "$www_subdomain" | grep -Fq 'NXDOMAIN'; then
                www_alive=1
            fi

            if dig @1.1.1.1 "$new_entry" | grep -Fq 'NXDOMAIN'; then
                if [[ "$www_alive" -eq 0 ]]; then
                    echo -e "\nThe domain is dead. Not added."
                    continue
                fi
                
                new_entry="$www_subdomain"
                
                cp "$domains_file" "$domains_file.bak"

                echo "$new_entry" >> "$domains_file"
                
                echo -e "\nAdded to blocklist: $new_entry"

                awk NF "$domains_file" > tmp1.txt

                sort tmp1.txt -o "$domains_file" 

                rm tmp*.txt
                
                continue
            fi

            cp "$domains_file" "$domains_file.bak"

            echo "$new_entry" >> "$domains_file"
            
            if [[ "$www_alive" -eq 1 ]]; then
                echo -e "\nAdded to blocklist:\n$new_entry\n$www_subdomain" 
                echo "$www_subdomain" >> "$domains_file"
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
                echo -e "\nInvalid entry."
                continue
            fi

            if grep -xFq "$new_entry" "$blacklist_file"; then
                echo "The domain is already in the blacklist. Not added."
                continue
            fi

            add_entry "$list" "$blacklist_file"
            
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

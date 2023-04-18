#!/bin/bash

domains_file="domains.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"

function remove_entry {
    # Remove the minus sign
    new_entry=$(echo "$new_entry" | cut -c 2-)

    # Remove the entry if it's in the list
    if grep -q "^$new_entry$" "$2"; then
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

            read -p "Enter the new entry (add '-' to remove entry): " new_entry

            # Change the new entry to lowercase
            new_entry="${new_entry,,}"

            # Remove a domain from the blocklist
            if [[ $new_entry == -* ]]; then
                remove_entry "$list" "$domains_file"
                continue
            fi

            # Check if the entry is valid
            if ! [[ $new_entry =~ ^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$ ]]; then
                echo "Invalid entry"
                continue
            fi

            # Test if the entry is dead
            if dig @1.1.1.1 "$new_entry" | grep -q 'NXDOMAIN'; then
                echo -e "\nThe domain is dead. Not added."
                continue
            fi

            # Backup the domains file before making any changes
            cp "$domains_file" "$domains_file.bak"

            # Check if the new entry is already in the list
            if grep -q "^$new_entry$" "$domains_file"; then
                echo "The entry is already in the blocklist"
                continue
            fi

            # Add the new entry
            echo "$new_entry" >> "$domains_file"
            echo -e "\nAdded to blocklist: $new_entry"

            # Remove empty lines
            awk NF "$domains_file" > tmp1.txt

            # Save changes and sort alphabetically
            sort -o "$domains_file" tmp1.txt

            # Remove temporary file
            rm tmp1.txt
            continue
            ;;
        2)
            echo "Whitelist"
            list="whitelist"

            read -p "Enter the new entry (add '-' to remove entry): " new_entry

            # Change the new entry to lowercase
            new_entry="${new_entry,,}"

            # Remove a term from the whitelist
            if [[ $new_entry == -* ]]; then
                remove_entry "$list" "$whitelist_file"
                continue
            fi
             
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
            echo "Blacklist"
            list="blacklist"

            read -p "Enter the new entry (add '-' to remove entry): " new_entry

            # Change the new entry to lowercase
            new_entry="${new_entry,,}"

            # Remove domain from the blacklist
            if [[ $new_entry == -* ]]; then
                remove_entry "$list" "$blacklist_file"
                continue
            fi

            # Check if the entry is valid
            if ! [[ $new_entry =~ ^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$ ]]; then
                echo "Invalid entry"
                continue
            fi

            # Check if the new entry is already in the list
            if grep -xq "$new_entry" "$blacklist_file"; then
                echo "The domain is already in the blacklist"
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
            exit 0  
            ;;
        *)
            echo "Invalid option selected"

            # Go back to options prompt
            continue  
            ;;
    esac
done

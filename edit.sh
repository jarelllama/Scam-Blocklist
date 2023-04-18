#!/bin/bash

domains_file="domains.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"

while true; do
    echo "Choose which list to add to:"
    echo "1. Blocklist"
    echo "2. Whitelist"
    echo "3. Blacklist"
    read choice

    read -p "Enter the new entry (add '-' to remove entry): " new_entry

    # Change the new entry to lowercase
    new_entry="${new_entry,,}"

    case "$choice" in
        1)
            echo "Blocklist"
            # Add the new entry if the domain isn't already in the blocklist
            if grep -q "^$new_entry$" "$domains_file"; then
                echo "The domain is already in the blocklist"
            else
                # Check if domain is dead

                echo "$new_entry" >> "$domains_file"

                # Remove empty lines
                awk NF "$domains_file" > tmp1.txt

                # Sort alphabetically
                sort -o "$domains_file" tmp1.txt

                # Remove temporary file
                rm tmp1.txt
            fi

            # Go back to options prompt
            continue
            ;;
        2)
            echo "Whitelist"
            # Add the new entry if a similar term isn't already in the whitelist
            if grep -Fiq "$new_entry" "$whitelist_file"; then
                existing_entry=$(grep -Fi "$new_entry" "$whitelist_file" | head -n 1)
                echo "A similar term is already in the whitelist: $existing_entry"
            else
                echo "$new_entry" >> "$whitelist_file"

                # Remove empty lines
                awk NF "$whitelist_file" > tmp1.txt

                # Sort alphabetically
                sort -o "$whitelist_file" tmp1.txt

                # Remove temporary file
                rm tmp1.txt
            fi

            # Go back to options prompt
            continue
            ;;
        3)
            echo "Blacklist"
            # Add the new entry if the domain isn't already in the blacklist
            if grep -q "^$new_entry$" "$blacklist_file"; then
                echo "The domain is already in the blacklist"
            else
                echo "$new_entry" >> "$blacklist_file"

                # Remove empty lines
                awk NF "$blacklist_file" > tmp1.txt

                # Sort alphabetically
                sort -o "$blacklist_file" tmp1.txt

                # Remove temporary file
                rm tmp1.txt
            fi

            # Go back to options prompt
            continue
            ;;
        *)
            echo "Invalid option selected"

            # Go back to options prompt
            continue  
            ;;
    esac
done

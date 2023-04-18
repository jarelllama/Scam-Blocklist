#!/bin/bash

domains_file="domains.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"

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

            read -p "Enter the new entry (add '-' to remove entry): " new_entry

            # Change the new entry to lowercase
            new_entry="${new_entry,,}"

            # Remove domain from the blocklist
            if [[ $new_entry == -* ]]; then
                domain=$(echo "$new_entry" | cut -c 2-)
                sed -i "/^$domain$/d" "$domains_file"
                echo -e "\nRemoved from blocklist: $new_entry"
            else
                # Test if the new entry is dead
                if dig @1.1.1.1 "$new_entry" | grep -q 'NXDOMAIN'; then
                    echo -e "\nThe domain is dead. Not added."
                else
                    # Add the new entry if the domain isn't already in the blocklist
                    if grep -q "^$new_entry$" "$domains_file"; then
                        echo "The domain is already in the blocklist"
                    else
                        echo "$new_entry" >> "$domains_file"
                        echo -e "\nAdded to blocklist: $new_entry"

                        # Remove empty lines
                        awk NF "$domains_file" > tmp1.txt

                        # Sort alphabetically
                        sort -o "$domains_file" tmp1.txt

                        # Remove temporary file
                        rm tmp1.txt
                    fi
                fi
            fi

            # Go back to options prompt
            continue
            ;;
        2)
            echo "Whitelist"

            read -p "Enter the new entry (add '-' to remove entry): " new_entry

            # Change the new entry to lowercase
            new_entry="${new_entry,,}"

            # Remove term from the whitelist
            if [[ $new_entry == -* ]]; then
                term=$(echo "$new_entry" | cut -c 2-)
                sed -i "/$term/d" "$whitelist_file"
                echo -e "\nRemoved from whitelist: $new_entry"
            else
                # Add the new entry if a similar term isn't already in the whitelist
                if grep -Fiq "$new_entry" "$whitelist_file"; then
                    existing_entry=$(grep -Fi "$new_entry" "$whitelist_file" | head -n 1)
                    echo "A similar term is already in the whitelist: $existing_entry"
                else
                    echo -e "\nAdded to whitelist: $new_entry"
                    echo "$new_entry" >> "$whitelist_file"

                    # Remove empty lines
                    awk NF "$whitelist_file" > tmp1.txt

                    # Sort alphabetically
                    sort -o "$whitelist_file" tmp1.txt

                    # Remove temporary file
                    rm tmp1.txt
                fi
            fi

            # Go back to options prompt
            continue
            ;;
        3)
            echo "Blacklist"

            read -p "Enter the new entry (add '-' to remove entry): " new_entry

            # Change the new entry to lowercase
            new_entry="${new_entry,,}"

            # Remove domain from the blacklist
            if [[ $new_entry == -* ]]; then
                domain=$(echo "$new_entry" | cut -c 2-)
                sed -i "/^$domain$/d" "$blacklist_file"
                echo -e "\nRemoved from blacklist: $new_entry"
            else
                # Add the new entry if the domain isn't already in the blacklist
                if grep -q "^$new_entry$" "$blacklist_file"; then
                    echo "The domain is already in the blacklist"
                else
                    echo -e "\nAdded to blacklist: $new_entry"
                    echo "$new_entry" >> "$blacklist_file"

                    # Remove empty lines
                    awk NF "$blacklist_file" > tmp1.txt

                    # Sort alphabetically
                    sort -o "$blacklist_file" tmp1.txt

                    # Remove temporary file
                    rm tmp1.txt
                fi
            fi

            # Go back to options prompt
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

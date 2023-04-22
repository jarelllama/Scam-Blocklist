#!/bin/bash

domains_file="domains"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="toplist.txt"

function update_header {
    num_domains=$(wc -l < "$domains_file")

    echo "# Title: Jarelllama's Scam Blocklist
# Description: Blocklist for scam sites extracted from Google
# Homepage: https://github.com/jarelllama/Scam-Blocklist
# Source: https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/domains
# License: GNU GPLv3 (https://www.gnu.org/licenses/gpl-3.0.en.html)
# Last modified: $(date -u)
# Total number of domains: $num_domains
" | cat - "$domains_file" > tmp1.txt

    mv tmp1.txt "$domains_file"
}

function edit_blocklist {
    echo "Blocklist"
    
    cp "$domains_file" "$domains_file.bak"

    # Strip the blocklist header (title, description, homepage, etc.)
    tail -n +9 "$domains_file" > tmp1.txt

    mv tmp1.txt "$domains_file"

    read -p $'Enter the new entry (add \'-\' to remove entry):\n' new_entry

    remove_entry=0

    if [[ "$new_entry" == -* ]]; then
        new_entry="${new_entry#-}"
        remove_entry=1
    fi

    new_entry="${new_entry,,}"

    new_entry="${new_entry#*://}"

    new_entry="${new_entry%%/*}"

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
        if ! grep -xFqf tmp_entries.txt "$domains_file"; then
            echo -e "\nDomain not found in blocklist: $new_entry"
            return
        fi

        echo -e "\nDomains removed:"
        comm -12 "$domains_file" tmp_entries.txt

        comm -23 "$domains_file" tmp_entries.txt > tmp1.txt

        mv tmp1.txt "$domains_file"

        rm tmp*.txt

        return
    fi

    if ! [[ "$new_entry" =~ ^[[:alnum:].-]+\.[[:alnum:]]{2,}$ ]]; then
        echo -e "\nInvalid domain. Not added."
        return
    fi

    if grep -xFf tmp_entries.txt "$toplist_file" | grep -vxFqf "$blacklist_file"; then
        echo -e "\nThe domain is found in the toplist. Not added."
        echo "Matches in toplist:"
        grep -xFf tmp_entries.txt  "$toplist_file" | grep -vxFf "$blacklist_file"
        return
    fi

    touch tmp_alive_entries.txt

    while read -r entry; do
        if dig @1.1.1.1 "$entry" | grep -Fq 'NXDOMAIN'; then
            return
        fi
        echo "$entry" >> tmp_alive_entries.txt
    done < tmp_entries.txt

    if ! [[ -s tmp_alive_entries.txt ]]; then
        echo -e "\nThe domain is dead. Not added."
        return
    fi

    mv tmp_alive_entries.txt tmp_entries.txt
  
    # This checks if there are no unique entries in the new entries file
    if [[ $(comm -23 tmp_entries.txt "$domains_file" | wc -l) -eq 0 ]]; then
        echo -e "\nThe domain is already in the blocklist. Not added."
        return
    fi

    echo -e "\nDomains added:"
    comm -23 tmp_entries.txt "$domains_file"

    cat tmp_entries.txt >> "$domains_file" 

    sort -u "$domains_file" -o "$domains_file"

    rm tmp*.txt

    update_header
}

function edit_whitelist {
    echo "Whitelist"

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
            return
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
    echo -e "\nChoose which list to add to:"
    echo "1. Blocklist"
    echo "2. Whitelist"
    echo "3. Blacklist"
    echo "4. Exit"
    read choice

    case "$choice" in
        1)
            edit_blocklist
            continue
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
            exit 0  
            ;;
        *)
            echo -e "\nInvalid option."
            continue  
            ;;
    esac
done

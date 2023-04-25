#!/bin/bash

raw_file="data/raw.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="data/toplist.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

function prep_entry {
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

    echo "$new_entry" > entries.tmp

    echo "$www_subdomain" >> entries.tmp
            
    sort entries.tmp -o entries.tmp
}

function edit_blocklist {
    echo "BLOCKLIST"
    
    cp "$raw_file" "$raw_file.bak"

    grep -vE '^(#|$)' "$raw_file" > raw.tmp

    prep_entry
            
    if [[ "$remove_entry" -eq 1 ]]; then
        if ! grep -xFqf entries.tmp raw.tmp; then
            echo -e "\nDomain not found in blocklist: $new_entry"
            return
        fi

        echo -e "\nDomains removed:"
        comm -12 raw.tmp entries.tmp

        comm -23 raw.tmp entries.tmp > "$raw_file"

        return
    fi

    if ! [[ "$new_entry" =~ ^[[:alnum:].-]+\.[[:alnum:]]{2,}$ ]]; then
        echo -e "\nInvalid domain. Not added."
        return
    fi

    if grep -xFf entries.tmp "$toplist_file" | grep -vxFqf "$blacklist_file"; then
        echo -e "\nThe domain is found in the toplist. Not added."
        echo "Matches in toplist:"
        grep -xFf entries.tmp  "$toplist_file" | grep -vxFf "$blacklist_file"
        return
    fi

    touch alive_entries.tmp

    while read -r entry; do
        if dig @1.1.1.1 "$entry" | grep -Fq 'NXDOMAIN'; then
            continue
        fi
        echo "$entry" >> alive_entries.tmp
    done < entries.tmp

    if ! [[ -s alive_entries.tmp ]]; then
        echo -e "\nThe domain is dead. Not added."
        return
    fi

    mv alive_entries.tmp entries.tmp
  
    # This checks if there are no unique entries in the new entries file
    if grep -xFqf entries.tmp raw.tmp; then
        echo -e "\nThe domain is already in the blocklist. Not added."
        return
    fi        

    echo -e "\nDomains added:"
    comm -23 entries.tmp raw.tmp

    cat entries.tmp >> raw.tmp 

    sort -u raw.tmp -o "$raw_file"
}

function edit_whitelist {
    echo "WHITELIST"

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

    # Check if the entry contains whitespaces or is empty
    if [[ "$new_entry" =~ [[:space:]] || -z "$new_entry" ]]; then
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
    echo "BLACKLIST"

    prep_entry
            
    if [[ "$remove_entry" -eq 1 ]]; then
        if ! grep -xFqf entries.tmp "$blacklist_file"; then
            echo -e "\nDomain not found in blacklist: $new_entry"
            return
        fi

        echo -e "\nDomains removed:"
        comm -12 "$blacklist_file" entries.tmp

        comm -23 "$blacklist_file" entries.tmp > tmp1.tmp

        mv tmp1.tmp "$blacklist_file"

        return
    fi

    if ! [[ "$new_entry" =~ ^[[:alnum:].-]+\.[[:alnum:]]{2,}$ ]]; then
        echo -e "\nInvalid domain. Not added."
        return
    fi

    touch alive_entries.tmp

    while read -r entry; do
        if dig @1.1.1.1 "$entry" | grep -Fq 'NXDOMAIN'; then
            continue
        fi
        echo "$entry" >> alive_entries.tmp
    done < entries.tmp

    if ! [[ -s alive_entries.tmp ]]; then
        echo -e "\nThe domain is dead. Not added."
        return
    fi

    mv alive_entries.tmp entries.tmp
  
    # This checks if there are no unique entries in the new entries file
    if grep -xFqf entries.tmp "$blacklist_file"; then
        echo -e "\nThe domain is already in the blacklist. Not added."
        return
    fi

    echo -e "\nDomains added:"
    comm -23 entries.tmp "$blacklist_file"

    cat entries.tmp >> "$blacklist_file" 

    sort -u "$blacklist_file" -o "$blacklist_file"
}

function check_entry {
    read -p $'\nEnter the entry to check:\n' check_entry
    if ! grep -xFq "$check_entry" "$raw_file"; then
        echo -e "\nThe entry is not present."
        if ! grep -Fq "$check_entry" "$raw_file"; then
            return
        fi
        echo "Similar entries:"
        grep -F "$check_entry" "$raw_file"
        return
    fi
    echo -e "\nThe entry is present."
    grep -xFq "$check_entry" "$raw_file"
}

function push_changes {
    echo -e "Push lists changes\n"

    git config user.email "$github_email"
    git config user.name "$github_name"

    git add "$raw_file"
    git commit -qm "Update $raw_file"
    git add "$whitelist_file"
    git commit -qm "Update $whitelist_file"
    git add "$blacklist_file"
    git commit -qm "Update $blacklist_file"
    git push
}

while true; do
    echo -e "\nEdit Lists Menu:"
    echo "1. Blocklist"
    echo "2. Whitelist"
    echo "3. Blacklist"
    echo "c. Check blocklist entry"
    echo "p. Push lists changes"
    echo "x. Exit/return"
    read choice

    case "$choice" in
        1)
            edit_blocklist
            rm *.tmp
            continue
            ;;
        2)
            edit_whitelist
            continue
            ;;
        3)
            edit_blacklist
            rm *.tmp
            continue
            ;;
        c)
            check_entry
            continue
            ;;
        p)
            push_changes

            if [[ -f *.tmp ]]; then
                rm *.tmp
            fi

            exit 0
            ;;
        x)
            if [[ -f *.tmp ]]; then
                rm *.tmp
            fi

            # Check if the script was sourced by another script
            if [[ "${#BASH_SOURCE[@]}" -gt 1 && "${BASH_SOURCE[0]}" != "${0}" ]]; then
                return
            fi

            exit 0  
            ;;
        *)
            echo -e "\nInvalid option."
            continue  
            ;;
    esac
done

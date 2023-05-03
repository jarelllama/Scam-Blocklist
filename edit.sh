#!/bin/bash

raw_file="data/raw.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="data/toplist.txt"
subdomains_file="data/subdomains.txt"
github_email='91372088+jarelllama@users.noreply.github.com'
github_name='jarelllama'

git config user.email "$github_email"
git config user.name "$github_name"

function prep_entry {
    read -p $'Enter the new entry (add \'-\' to remove entry):\n' entry

    remove_entry=0

    if [[ "$entry" == -* ]]; then
        entry="${entry#-}"
        remove_entry=1
    fi

    entry="${entry,,}"

    entry="${entry#*://}"

    entry="${entry%%/*}"

    if ! [[ "$entry" == *.* ]]; then
        entry="${entry}.com"
    fi

    # Assume the entry is a second-level domain and has no subdomain
    sld="$entry"

    while read -r subdomain; do
        if ! [[ "$entry" == "$subdomain".* ]]; then
            continue
        fi
        # Strip the subdomain to the second-level domain
        sld="${entry#"${subdomain}".}"
    done < "$subdomains_file"

    echo "$sld" > entries.tmp

    echo "www.${sld}" >> entries.tmp

    echo "m.${sld}" >> entries.tmp

    sort entries.tmp -o entries.tmp
}

function edit_blocklist {
    echo "BLOCKLIST"
    
    cp "$raw_file" "${raw_file}.bak"

    prep_entry
            
    if [[ "$remove_entry" -eq 1 ]]; then
        # Check if the new entries are unique (not in the blocklist)
        if comm -23 entries.tmp "$raw_file" | grep -q . ; then
            echo -e "\nDomain not found in blocklist: $entry"
            return
        fi

        echo -e "\nDomains removed:"
        comm -12 "$raw_file" entries.tmp

        comm -23 "$raw_file" entries.tmp > raw.tmp
        
        mv raw.tmp "$raw_file"

        return
    fi

    if ! [[ "$entry" =~ ^[[:alnum:].-]+\.[[:alnum:]-]{2,}$ ]]; then
        echo -e "\nInvalid domain. Not added."
        return
    fi

    # The toplist is checked before removing dead domains to find potential subdomains in the toplist
    comm -12 entries.tmp "$toplist_file" | grep -vxFf "$blacklist_file" > in_toplist.tmp

    if [[ -s in_toplist.tmp ]]; then
        echo -e "\nThe domain is found in the toplist. Not added."
        echo "Matches in toplist:"
        cat in_toplist.tmp
        return
    fi

    # mv shows an error when the file doesnt exist
    touch alive_entries.tmp
    cat entries.tmp | xargs -I{} -P6 bash -c "
        if ! dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> alive_entries.tmp
        fi
    "

    if ! [[ -s alive_entries.tmp ]]; then
        echo -e "\nThe domain is dead. Not added."
        return
    fi

    # The dead check messes up the order
    sort alive_entries.tmp -o entries.tmp
  
    # Check if the new entries are not unique (already in the blocklist)
    if ! comm -23 entries.tmp "$raw_file" | grep -q . ; then
        echo -e "\nThe domain is already in the blocklist. Not added."
        return
    fi        

    echo -e "\nDomains added:"
    comm -23 entries.tmp "$raw_file"

    cat entries.tmp >> "$raw_file" 

    sort -u "$raw_file" -o "$raw_file"
}

function edit_whitelist {
    echo "WHITELIST"

    read -p $'Enter the new entry (add \'-\' to remove entry):\n' entry

    entry="${entry,,}"

    if [[ "$entry" == -* ]]; then
        entry="${entry#-}"
        if ! grep -xFq "$entry" "$whitelist_file"; then
            echo -e "\nEntry not found in whitelist: $entry"
            return
        fi
        echo -e "\nRemoved from whitelist: $entry"
        sed -i "/^$entry$/d" "$whitelist_file"
        return
    fi

    # Check if the entry contains whitespaces or is empty
    if [[ "$entry" =~ [[:space:]] || -z "$entry" ]]; then
        echo -e "\nInvalid entry. Not added."
        return
    fi
    
    if grep -Fq "$entry" "$whitelist_file"; then
        existing_entry=$(grep -F "$entry" "$whitelist_file" | head -n 1)
        echo -e "\nA similar term is already in the whitelist: $existing_entry"
        return
    fi

    echo -e "\nAdded to whitelist: $entry"
    echo "$entry" >> "$whitelist_file"

    sort "$whitelist_file" -o "$whitelist_file"
}

function edit_blacklist {
    echo "BLACKLIST"

    prep_entry
            
    if [[ "$remove_entry" -eq 1 ]]; then
        if ! grep -xFqf entries.tmp "$blacklist_file"; then
            echo -e "\nDomain not found in blacklist: $entry"
            return
        fi

        echo -e "\nDomains removed:"
        comm -12 "$blacklist_file" entries.tmp

        comm -23 "$blacklist_file" entries.tmp > blacklist.tmp

        mv blacklist.tmp "$blacklist_file"

        return
    fi

    if ! [[ "$entry" =~ ^[[:alnum:].-]+\.[[:alnum:]-]{2,}$ ]]; then
        echo -e "\nInvalid domain. Not added."
        return
    fi

    touch alive_entries.tmp
    cat entries.tmp | xargs -I{} -P6 bash -c "
        if ! dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> alive_entries.tmp
        fi
    "

    if ! [[ -s alive_entries.tmp ]]; then
        echo -e "\nThe domain is dead. Not added."
        return
    fi

    sort alive_entries.tmp -o entries.tmp

    if ! comm -23 entries.tmp "$blacklist_file" | grep -q . ; then
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
    
    check_entry="${check_entry,,}"

    check_entry="${check_entry#*://}"

    check_entry="${check_entry%%/*}"
    
    if ! [[ "$check_entry" == *.* ]]; then
        check_entry="${check_entry}.com"
    fi

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
}

function push_changes {
    echo -e "Push lists changes\n"

    git add "$raw_file" "$whitelist_file" "$blacklist_file"
    git commit -m "Update list(s)"
    git push
}

while true; do
    echo -e "\nEdit Lists Menu:"
    echo "b. Blocklist"
    echo "w. Whitelist"
    echo "l. Blacklist"
    echo "c. Check blocklist entry"
    echo "p. Push list(s) changes"
    echo "x. Exit/return"
    read choice

    case "$choice" in
        b)
            edit_blocklist
            rm *.tmp
            ;;
        w)
            edit_whitelist
            ;;
        l)
            edit_blacklist
            rm *.tmp
            ;;
        c)
            check_entry
            ;;
        p)
            push_changes

            find . -maxdepth 1 -type f -name "*.tmp" -delete

            exit 0
            ;;
        x)
            find . -maxdepth 1 -type f -name "*.tmp" -delete

            # Check if the script was sourced by another script
            if [[ "${#BASH_SOURCE[@]}" -gt 1 && "${BASH_SOURCE[0]}" != "${0}" ]]; then
                return
            fi

            exit 0  
            ;;
        *)
            echo -e "\nInvalid option."  
            ;;
    esac
done

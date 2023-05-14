#!/bin/bash

raw_file="data/raw.txt"
whitelist_file="data/whitelist.txt"
blacklist_file="data/blacklist.txt"
toplist_file="data/toplist.txt"
subdomains_file="data/subdomains.txt"

trap "find . -maxdepth 1 -type f -name '*.tmp' -delete" EXIT

function format_entry() {
    remove_entry=0
    if [[ "$entry" == -* ]]; then
        entry="${entry#-}"
        remove_entry=1
    fi

    entry="${entry,,}"

    entry="${entry#*://}"

    entry="${entry%%/*}"

    [[ "$entry" == *.* ]] || entry="${entry}.com"

    while read -r subdomain; do
        entry="${entry#"${subdomain}".}"
    done < "$subdomains_file"
}

function remove_entry() {
    if [[ "$remove_entry" -eq 1 ]]; then
        if ! grep -xFq "$entry" "$2"; then
            echo -e "\nEntry not found in the ${1}: $entry"
            return
        fi
        echo -e "\nRemoved from the ${1}: $entry"
        sed -i "/^${entry}$/d" "$2"
        return
    fi
}

function edit_blocklist {
    echo "BLOCKLIST"

    read -rp $'Enter the new entry (add \'-\' to remove entry):\n' entry

    format_entry "$entry"
            
    remove_entry blocklist "$raw_file"

    if ! [[ "$entry" =~ ^[[:alnum:].-]+\.[[:alnum:]-]{2,}$ ]]; then
        echo -e "\nInvalid domain. Not added."
        return
    fi
  
    if grep -xF "$entry" "$raw_file"; then
        echo -e "\nThe domain is already in the blocklist. Not added."
        return
    fi

    if ! grep -xF "$entry" "$blacklist_file"; then
        echo "$entry" > with_subdomains.tmp

        while read -r subdomain; do
            echo "${subdomain}.${entry}" >> with_subdomains.tmp
        done < "$subdomains_file"
    
        if grep -xFf with_subdomains.tmp "$toplist_file"; then
            echo -e "\nThe domain is in the toplist. Not added."
            return
        fi
    fi

    if dig @1.1.1.1 "$entry" | grep -Fq 'NXDOMAIN'; then
        echo -e "\nThe domain is dead. Not added."
        return
    fi

    echo -e "\nAdded to the blocklist: ${entry}"

    echo "$entry" >> "$raw_file"

    sort "$raw_file" -o "$raw_file"
}

function edit_whitelist {
    echo "WHITELIST"

    read -rp $'Enter the new entry (add \'-\' to remove entry):\n' entry

    format_entry "$entry"

    remove_entry whitelist "$whitelist_file"

    # Check if the entry contains whitespaces or is empty
    if [[ "$entry" =~ [[:space:]] || -z "$entry" ]]; then
        echo -e "\nInvalid entry. Not added."
        return
    fi
    
    if grep -Fq "$entry" "$whitelist_file"; then
        echo -e "\nSimilar term(s) are already in the whitelist:"
        grep -F "$entry" "$whitelist_file"
        return
    fi

    echo -e "\nAdded to the whitelist: ${entry}"

    echo "$entry" >> "$whitelist_file"

    sort "$whitelist_file" -o "$whitelist_file"
}

function edit_blacklist {
    echo "BLACKLIST"

    read -rp $'Enter the new entry (add \'-\' to remove entry):\n' entry

    format_entry "$entry"
            
    remove_entry blacklist "$blacklist_file"

    if ! [[ "$entry" =~ ^[[:alnum:].-]+\.[[:alnum:]-]{2,}$ ]]; then
        echo -e "\nInvalid domain. Not added."
        return
    fi

    if grep -xF "$entry" "$blacklist_file"; then
        echo -e "\nThe domain is already in the blocklist. Not added."
        return
    fi
    
    if dig @1.1.1.1 "$entry" | grep -Fq 'NXDOMAIN'; then
        echo -e "\nThe domain is dead. Not added."
        return
    fi

    echo -e "\nAdded to the blacklist: ${entry}"

    echo "$entry" >> "$blacklist_file"

    sort "$blacklist_file" -o "$blacklist_file"
}

function check_entry {
    read -rp $'\nEnter the entry to check:\n' entry

    format_entry "$entry"

    if ! grep -xFq "$entry" "$raw_file"; then
        echo -e "\nThe entry is not present: $entry"
        # Check if there are similar entries
        grep -Fq "$entry" "$raw_file" || return
        echo "Similar entries:"
        grep -F "$entry" "$raw_file"
        return
    fi
    echo -e "\nThe entry is present: $entry"
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
    read -r choice

    case "$choice" in
        b)
            edit_blocklist
            ;;
        w)
            edit_whitelist
            ;;
        l)
            edit_blacklist
            ;;
        c)
            check_entry
            ;;
        p)
            push_changes
            exit 0
            ;;
        x)
            # Check if the script was sourced by another script
            [[ "${#BASH_SOURCE[@]}" -gt 1 && "${BASH_SOURCE[0]}" != "${0}" ]] \
                && return

            exit 0  
            ;;
        *)
            echo -e "\nInvalid option."  
            ;;
    esac
done

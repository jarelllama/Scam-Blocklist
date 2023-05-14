#!/bin/bash

raw_file="data/raw.txt"
optimised_entries="data/optimised_entries.txt"
optimiser_whitelist="data/optimiser_whitelist.txt"

trap "find . -maxdepth 1 -type f -name '*.tmp' -delete" exit

while true; do
    grep -E '\..*\.' data/raw.txt \
        | cut -d '.' -f2- \
        | awk -F '.' '$1 ~ /.{4,}/ {print}' \
        | sort \
        | uniq -d > 1.tmp
    
    comm -23 1.tmp "$optimiser_whitelist" > 2.tmp
    comm -23 2.tmp "$optimised_entries" > 2.tmp
    comm -23 3.tmp "$raw_file" > domains.tmp

    domains=$(cat domains.tmp)

    if [[ -z "$domains" ]]; then
        echo -e "\nNo potential optimizations found."
    else
        numbered_domains=$(echo "$domains" | awk '{print NR ". " $0}')
        echo -e "\nPotential optimisations:"
        echo "${numbered_domains}"

        echo -e "\nSelect a domain with its number."
    fi
    echo "Enter 'p' to push changes."
    echo "Enter 'x' to exit."
    read -r chosen_number

    [[ "$chosen_number" == 'x' ]] && exit 0
    
    if [[ "$chosen_number" == 'p' ]]; then
        echo -e "\nPushing changes..."
        git add "$raw_file" "$optimised_entries" "$optimiser_whitelist"
        git commit -m "Optimise blocklist"
        git push
        exit 0
    fi

    chosen_domain=$(echo "$numbered_domains" | awk -v n="$chosen_number" '$1 == n {print $2}')

    echo -e "\nChose what to do with '$chosen_domain':"
    echo "b. Add to blocklist"
    echo "w. Add to whitelist"
    echo "x. Return"
    read -r choice
    
    case "$choice" in
        b)
            echo -e "\nAdded '${chosen_domain}'' to the blocklist."
            echo "$chosen_domain" >> "$raw_file"
            echo "$chosen_domain" >> "$optimised_entries"
            sort "$raw_file" -o "$raw_file"
            sort "$optimised_entries" -o "$optimised_entries"
            ;;
        w)
            echo -e "\nAdded '${chosen_domain}' to the whitelist."
            echo "$chosen_domain" >> "$optimiser_whitelist"
            sort "$optimiser_whitelist" -o "$optimiser_whitelist"
            ;;
    esac
done

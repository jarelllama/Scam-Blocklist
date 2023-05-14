#!/bin/bash

optimiser_blacklist="data/optimiser_blacklist.txt"
optimiser_whitelist="data/optimiser_whitelist.txt"

trap "find . -maxdepth 1 -type f -name '*.tmp' -delete" exit

grep -E '\..*\.' data/raw.txt \
    | cut -d '.' -f2- \
    | awk -F '.' '$1 ~ /.{4,}/ {print}' \
    | sort \
    | uniq -d > 1.tmp
    
comm -23 1.tmp "$optimiser_whitelist" > 2.tmp
comm -23 2.tmp "$optimiser_blacklist" > domains.tmp

while true; do
    domains=$(cat domains.tmp)

    numbered_domains=$(echo "$domains" | awk '{print NR " " $0}')
    echo "$numbered_domains"

    echo -e "\nSelect a domain"
    echo "or 'p' to push changes"
    echo "or 'x' to exit"
    read -r chosen_number

    [[ "$chosen_number" == 'x' ]] && exit 0
    
    if [[ "$chosen_number" == 'p' ]]; then
        echo -e "\nPushing changes..."
        git add "$raw_file" "$optimiser_blacklist" "$optimiser_blacklist"
        git commit -m "Optimise blocklist"
        git push
        exit 0
    fi

    chosen_domain=$(echo "$numbered_domains" | awk -v n="$chosen_number" '$1 == n {print $2}')

    echo -e "\nOptimiser Menu:"
    echo "b. Blacklist"
    echo "w. Whitelist"
    echo "x. Return"
    read -r choice
    
    case "$choice" in
        b)
            echo "$chosen_domain" >> "$raw_file"
            echo "$chosen_domain" >> "$optimiser_blacklist"
            sort "$raw_file" -o "$raw_file"
            sort "$optimiser_blacklist" -o "$optimiser_blacklist"
            ;;
        w)
            echo "$chosen_domain" >> "$optimiser_whitelist"
            sort "$optimiser_whitelist" -o "$optimiser_whitelist"
            ;;
    esac
done

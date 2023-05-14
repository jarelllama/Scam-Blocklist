#!/bin/bash

optimise_blacklist="data/optimise_blacklist"
optimise_whitelist="data/optimise_whitelist"

trap "find . -maxdepth 1 -type f -name '*.tmp' -delete" exit

#function print_domains() {
#    domains=$1
#    numbered_domains=$(echo "$domains" | awk '{print NR " " $0}')
#    echo "$numbered_domains"
#}

while true; do
    domains=$(grep -E '\..*\.' data/raw.txt \
        | cut -d '.' -f2- \
        | awk -F '.' '$1 ~ /.{4,}/ {print}' \
        | sort \
        | uniq -d \
        | grep -vF 'shop')

    numbered_domains=$(echo "$domains" | awk '{print NR " " $0}')
    echo "$numbered_domains"

    read -rp "Select a domain ('x' to exit): " chosen_number

    [[ "$chosen_number" == 'x' ]] && exit 0

    chosen_domain=$(echo "$domains" | awk -v n="$chosen_number" '$1 == n {print $2}')

    echo "$chosen_domain"

    read -rp "Add \"$chosen_domain\" to the blacklist (b) or whitelist (w)? " blacklist_or_whitelist
done
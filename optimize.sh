#!/bin/bash

optimise_blacklist="data/optimise_blacklist"
optimise_whitelist="data/optimise_whitelist"

trap "find . -maxdepth 1 -type f -name '*.tmp' -delete" exit

function print_domains() {
    domains=$1
    numbered_domains=$(echo "$domains" | awk '{print NR ". " $0}')
    echo "$numbered_domains"
}

while true; do
    domains=$(grep -E '\..*\.' data/raw.txt \
        | cut -d '.' -f2- \
        | awk -F '.' '$1 ~ /.{4,}/ {print}' \
        | sort \
        | uniq -d \
        | grep -vF 'shop')

    print_domains "$domains"

    read -rp "Select a domain ('x' to exit): " chosen_number

    [[ "$chosen_number" == 'x' ]] && exit 0

    chosen_domain=$(echo "$domains" | awk -v n="$chosen_number" '$0 ~ n {print $0}')

    echo "$chosen_domain"

    read -rp "Add \"$chosen_domain\" to the blacklist (b) or whitelist (w)? " blacklist_or_whitelist

  # Add the domain to the specified list
  if [[ "$blacklist_or_whitelist" == "b" ]]; then
    blacklist+=("$chosen_domain")
    echo "\"$chosen_domain\" added to the blacklist."
  elif [[ "$blacklist_or_whitelist" == "w" ]]; then
    whitelist+=("$chosen_domain")
    echo "\"$chosen_domain\" added to the whitelist."
  else
    echo "Invalid option. \"$chosen_domain\" was not added to any list."
  fi
done
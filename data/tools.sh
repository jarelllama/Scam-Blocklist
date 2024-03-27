#!/bin/bash

# Find root domains that occur more than once
# grep '\..*\.' raw.txt | awk -F '.' '{print $2"."$3"."$4}' | sort | uniq -d

function format {
    [[ ! -f "$1" ]] && return  # Return if file does not exist

    # Remove carriage return characters and trailing whitespaces
    sed -i 's/\r//g; s/[[:space:]]*$//' "$1"

    # For specific files/extensions:
    case "$1" in
        data/dead_domains.txt)  # Remove whitespaces, empty lines and duplicates
            sed 's/ //g; /^$/d' "$1" | awk '!seen[$0]++' > "${1}.tmp" && mv "${1}.tmp" "$1" ;;
        data/parked_domains.txt)  # Remove empty lines, sort and remove duplicates
            sed '/^$/d' | sort -u -o "$1" ;;
        *.txt|*.tmp)  # Remove whitespaces, empty lines, sort and remove duplicates
            sed 's/ //g; /^$/d' "$1" | sort -u -o "$1" ;;
    esac
}

function remove_parked_domains {
    raw_file="$1"
    parked_terms_file='data/parked_terms.txt'
    parked_domains_file='data/parked_domains.txt'

    split -n 12 -d "$raw_file"
    check_for_parked "x00" & check_for_parked "x01" &
    check_for_parked "x02" & check_for_parked "x03" &
    check_for_parked "x04" & check_for_parked "x05" &
    check_for_parked "x06" & check_for_parked "x07" &
    check_for_parked "x08" & check_for_parked "x09" &
    check_for_parked "x10" & check_for_parked "x11"

    format "$parked_domains_file"
    comm -23 "$raw_file" "$parked_domains_file" > temp && mv temp "$raw_file"
}

function check_for_parked {
    total=$(wc -l < "$1")
    count=1
    # Check for parked message in site's HTML
    while read -r domain; do
        (( "$count" % 10 == 0 )) && printf "%s/%s\n" "$count" "$total"
        if grep -qiFf "$parked_terms_file" <<< "$(curl -sL --max-time 1 "http://${domain}/")"; then
            printf "%s | Parked: %s\n" "$1" "$domain"
            printf "%s\n" "$domain" >> "parked_domains_${1}.tmp"
        fi
        ((count++))
    done < "$1"
    [[ -f "parked_domains_${1}.tmp" ]] && cat "parked_domains_${1}.tmp" >> "$parked_domains_file"
    rm "$1"
    rm "parked_domains_${1}.tmp"
}

[[ "$1" == 'format' ]] && format "$2"
[[ "$1" == 'parked' ]] && remove_parked_domains "$2"
exit 0

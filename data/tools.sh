#!/bin/bash

# Find root domains that occur more than once
# grep '\..*\.' raw.txt | awk -F '.' '{print $2"."$3"."$4}' | sort | uniq -d

# Format files
function format {
    [[ ! -f "$1" ]] && return  # Return if file does not exist

    # Remove carriage return characters and trailing whitespaces
    sed -i 's/\r//g; s/[[:space:]]*$//' "$1"

    # For specific files/extensions:
    case "$1" in
        data/pending/*)  # Remove whitespaces, empty lines, sort and remove duplicates
            sed 's/ //g; /^$/d' "$1" | sort -u -o "$1" ;;
        data/dead_domains.txt)  # Remove whitespaces, empty lines and duplicates
            sed 's/ //g; /^$/d' "$1" | awk '!seen[$0]++' > "${1}.tmp" && mv "${1}.tmp" "$1";;
        *.txt|*.tmp)  # Remove whitespaces, empty lines, sort and remove duplicates
            sed 's/ //g; /^$/d' "$1" | sort -u -o "$1" ;;
    esac
}

[[ "$1" == 'format' ]] && format "$2"
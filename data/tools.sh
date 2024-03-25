#!/bin/bash

# Format files
function format {
    [[ ! -f "$1" ]] && return  # Return if file does not exist

    # Remove carraige return characters and trailing whitespaces
    sed -i 's/\r//g; s/[[:space:]]*$//' "$1"

    # For specific files/extensions:
    case "$1" in
        *dead_domains*)  # Remove whitespaces, empty lines and duplicates
            tr -d ' ' < "$1" | sed '/^$/d' | awk '!seen[$0]++' > "${1}.tmp" ;;
        *.txt)  # Remove whitespaces, empty lines, sort and remove duplicates
             tr -d ' ' < "$1" | sed '/^$/d' | sort -u > "${1}.tmp" ;;
    esac
    [[ -f "${1}.tmp" ]] && mv "${1}.tmp" "$1"
}

[[ "$1" == 'format' ]] && format "$2"
#!/bin/bash

# tools.sh is a shell wrapper intended to store commonly used functions.

# Function 'format' is called to standardize the format of a file.
#   $1: file to be formatted
format() {
    file="$1"
    [[ ! -f "$file" ]] && return

    # Applicable to all files:
    # Remove carriage return characters and trailing whitespaces
    sed -i 's/\r//g; s/[[:space:]]*$//' "$file"

    # Applicable to specific files/extensions:
    case "$file" in
        'data/dead_domains.txt'|'data/parked_domains.txt')
            # Remove whitespaces, empty lines, convert to lowercase, and duplicates
            sed 's/ //g; /^$/d' "$file" | tr '[:upper:]' '[:lower:]' \
                | awk '!seen[$0]++' > "${file}.tmp"
            ;;

        'config/parked_terms.txt')
            # Remove empty lines, convert to lowercase, sort and remove duplicates
            sed '/^$/d' "$file" | tr '[:upper:]' '[:lower:]' \
                | sort -u -o "${file}.tmp"
            ;;

        *.txt|*.tmp)
            # Remove whitespaces, empty lines, convert to lowercase, sort and remove duplicates
            sed 's/ //g; /^$/d' "$file" | tr '[:upper:]' '[:lower:]' \
                | sort -u -o "${file}.tmp"
            ;;
    esac

    mv "${file}.tmp" "$file" 2> /dev/null
}

[[ "$1" == 'format' ]] && format "$2"  # Pass the file from the caller

exit 0

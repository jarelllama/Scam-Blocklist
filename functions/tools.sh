#!/bin/bash

# tools.sh is a shell wrapper intended to store commonly used functions.

# Function 'format' is called to standardize the format of a file.
#   $1: file to be formatted
# Latest code review: 9 April 2024
format() {
    file="$1"

    [[ ! -f "$file" ]] && return

    # Applicable to all files:
    # Remove carriage return characters, empty lines, and trailing whitespaces
    sed -i 's/\r//g; /^$/d; s/[[:space:]]*$//' "$file"

    # Applicable to specific files/extensions:
    case "$file" in
        'data/dead_domains.txt'|'data/parked_domains.txt')
            # Remove whitespaces, convert to lowercase, and remove duplicates
            sed 's/[[:space:]]//g' "$file" | tr '[:upper:]' '[:lower:]' \
                | awk '!seen[$0]++' > "${file}.tmp"
            ;;
        'config/parked_terms.txt')
            # Convert to lowercase, sort, and remove duplicates
            tr '[:upper:]' '[:lower:]' < "$file" | sort -u -o "${file}.tmp"
            ;;
        *.txt|*.tmp)
            # Remove whitespaces, convert to lowercase, sort, and remove
            # duplicates
            sed 's/[[:space:]]//g' "$file" | tr '[:upper:]' '[:lower:]' \
                | sort -u -o "${file}.tmp"
            ;;
        *)
            return
            ;;
    esac

    [[ -f "${file}.tmp" ]] && mv "${file}.tmp" "$file"
}

# Function 'log_event' is called to log domain processing events into the
# domain log.
#   $1: domains to log stored in a variable
#   $2: event type (dead, whitelisted, etc.)
#   $3: source
# Latest code review: 8 April 2024
log_event() {
    timestamp="$(date -u +"%H:%M:%S %d-%m-%y")"

    # Return if no domains passed
    [[ -z "$1" ]] && return

    printf "%s\n" "$1" | awk -v event="$2" -v source="$3" -v time="$timestamp" \
        '{print time "," event "," $0 "," source}' >> config/domain_log.csv
}

function="$1"

case "$function" in
    format)
        format "$2"
        ;;
    log_event)
        log_event "$2" "$3" "$4"
        ;;
    *)
        printf "\nInvalid function passed.\n"
        exit 1
        ;;
esac

exit 0

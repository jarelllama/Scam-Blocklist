#!/bin/bash

# This script checks for parked/unparked domains and removes/adds
# them accordingly.

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly PARKED_TERMS='config/parked_terms.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly WILDCARDS='data/wildcards.txt'
readonly DOMAIN_LOG='config/domain_log.csv'

main() {
    for file in config/* data/*; do
        format_file "$file"
    done

    remove_parked_domains
    add_unparked_domains

    # Remove domains from light raw file that are not found in full raw file
    comm -12 "$RAW" "$RAW_LIGHT" > light.tmp
    mv light.tmp "$RAW_LIGHT"

    # Cache parked domains to filter out from newly retrieved domains
    # (done last to skip unparked domains check)
    cat parked_raw.tmp >> "$PARKED_DOMAINS"
    format_file "$PARKED_DOMAINS"
}

# Function 'removed_parked_domains' removes parked domains from the raw file.
remove_parked_domains() {
    # Exclude wildcards and root domains of subdomains
    comm -23 "$RAW" <(sort "$ROOT_DOMAINS" "$WILDCARDS") > raw.tmp

    retrieve_parked raw.tmp || return

    # Rename temporary parked file to be added into parked cache later
    mv parked_domains.tmp parked_raw.tmp

    # Remove parked domains from raw file
    comm -23 "$RAW" parked_domains.tmp > raw.tmp
    mv raw.tmp "$RAW"

    log_event "$(<parked_domains.tmp)" parked raw
}

# Function 'add_unparked_domains' finds unparked domains in the parked domains
# file and adds them back into the raw file.
add_unparked_domains() {
    retrieve_parked "$PARKED_DOMAINS"  # No need to return if no parked found

    # Get unparked domains (parked domains file is unsorted)
    unparked_domains="$(comm -23 <(sort "$PARKED_DOMAINS") <(sort parked_domains.tmp))"
    [[ -z "$unparked_domains" ]] && return

    # Keep only parked domains in parked domains file
    # grep is used here because the 'retrieve_parked' function messes with
    # the order of the entries
    grep -xFf parked_domains.tmp "$PARKED_DOMAINS" > parked.tmp
    mv parked.tmp "$PARKED_DOMAINS"

    # Add unparked domains to raw file
    printf "%s\n" "$unparked_domains" >> "$RAW"
    format_file "$RAW"

    log_event "$unparked_domains" unparked parked_domains_file
}

# Function 'retrieve_parked' efficiently checks for parked domains from a
# given file by running the checks in parallel.
# Input:
#   $1: file to process
# Output:
#   parked_domains.tmp
#   return 1 if parked domains not found
retrieve_parked() {
    printf "\n[info] Processing file %s\n" "$1"
    printf "[start] Analyzing %s entries for parked domains\n" "$(wc -l < "$1")"

    # Split file into 14 equal files
    split -d -l $(( $(wc -l < "$1") / 14 )) "$1"

    # Run checks in parallel
    find_parked x00 & find_parked x01 & find_parked x02 & find_parked x03 &
    find_parked x04 & find_parked x05 & find_parked x06 & find_parked x07 &
    find_parked x08 & find_parked x09 & find_parked x10 & find_parked x11 &
    find_parked x12 & find_parked x13 & find_parked x14 & find_parked x15
    wait
    rm x??

    # Collate parked domains (ignore not found errors)
    cat parked_domains_x??.tmp > parked_domains.tmp 2> /dev/null
    rm parked_domains_x??.tmp 2> /dev/null

    format_file parked_domains.tmp

    printf "[success] Found %s parked domains\n" "$(wc -l < parked_domains.tmp)"

    # Return 1 if no parked domains were found
    [[ ! -s parked_domains.tmp ]] && return 1 || return 0
}

# Function 'find_parked' queries sites from a given file for parked messages
# in their HTML.
# Input:
#   $1: file to process
# Output:
#   parked_domains_x??.tmp (if parked domains found)
find_parked() {
    [[ ! -f "$1" ]] && return

    # Track progress only for first split file
    if [[ "$1" == 'x00' ]]; then
        local track=true
        local count=1
    fi

    while read -r domain; do
        # Check for parked message in site's HTML
        if grep -qiFf "$PARKED_TERMS" \
            <<< "$(curl -sL --max-time 3 "http://${domain}/" | tr -d '\0')"; then
            printf "[info] Found parked domain: %s\n" "$domain"
            printf "%s\n" "$domain" >> "parked_domains_${1}.tmp"
        fi

        # Skip progress tracking if not first split file
        [[ "$track" != true ]] && continue

        if (( count % 100 == 0 )); then
            printf "[info] Analyzed %s%% of domains\n" "$(( count * 100 / $(wc -l < "$1") ))"
        fi

        (( count++ ))
    done < "$1"
}

# Function 'log_event' logs domain processing events into the domain log.
#   $1: domains to log stored in a variable.
#   $2: event type (dead, whitelisted, etc.)
#   $3: source
log_event() {
    [[ -z "$1" ]] && return  # Return if no domains in variable
    local source="$3"
    printf "%s\n" "$1" | awk -v type="$2" -v source="$source" -v time="$(date -u +"%H:%M:%S %d-%m-%y")" \
        '{print time "," type "," $0 "," source}' >> "$DOMAIN_LOG"
}

# Function 'format_file' calls a shell wrapper to standardize the format
# of a file.
#   $1: file to format
format_file() {
    bash functions/tools.sh format "$1"
}

cleanup() {
    find . -maxdepth 1 -type f -name "*.tmp" -delete
    find . -maxdepth 1 -type f -name 'x??' -delete

    # Prune old entries from parked domains file
    lines="$(wc -l < "$PARKED_DOMAINS")"
    if (( lines > 5000 )); then
        sed -i "1,$(( lines - 5000 ))d" "$PARKED_DOMAINS"
    fi
}

trap cleanup EXIT

main

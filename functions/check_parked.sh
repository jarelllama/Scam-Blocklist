#!/bin/bash

# This script checks for parked/unparked domains and
# removes/adds them accordingly.

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly PARKED_TERMS='config/parked_terms.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
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

    # Cache parked domains (done last to skip unparked domains check)
    cat parked_domains.tmp >> "$PARKED_DOMAINS"
    format_file "$PARKED_DOMAINS"
}

remove_parked_domains() {
    retrieve_parked "$RAW" || return

    # Remove parked domains from raw file
    comm -23 "$RAW" parked_domains.tmp > raw.tmp && mv raw.tmp "$RAW"

    log_event "$(<parked_domains.tmp)" parked raw
}

add_unparked_domains() {
    retrieve_parked "$PARKED_DOMAINS" || return

    # Get unparked domains
    unparked_domains="$(grep -vxFf parked_domains.tmp "$PARKED_DOMAINS")"

    # Keep only parked domains in parked domains file
    grep -xFF parked_domains.tmp "$PARKED_DOMAINS" > parked.tmp
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
#   parked_domains.tmp (if parked domains found)
#   exit status 1 (if parked domains not found)
retrieve_parked() {
    # Truncate temporary files between runs
    : > parked_domains.tmp  # File needs to exist to avoid not found errors
    find . -maxdepth 1 -type f -name "x??" -delete

    printf "\n[info] Processing file %s\n" "$1"
    printf "[start] Analyzing %s entries for parked domains\n" "$(wc -l < "$1")"

    # Split file into 12 equal files
    split -d -l $(( $(wc -l < "$1") / 12 )) "$1"

    # Run checks in parallel
    find_parked "x00" & find_parked "x01" &
    find_parked "x02" & find_parked "x03" &
    find_parked "x04" & find_parked "x05" &
    find_parked "x06" & find_parked "x07" &
    find_parked "x08" & find_parked "x09" &
    find_parked "x10" & find_parked "x11" &
    find_parked "x12" & find_parked "x13"
    wait

    # Return 1 if no parked domains were found
    [[ ! -s parked_domains.tmp ]] && return 1

    format_file parked_domains.tmp
}

# Function 'find_parked' queries sites from a given file for parked messages
# in their HTML.
# Input:
#   $1: file to process
# Output:
#   parked_domains.tmp (if parked domains found)
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
            <<< "$(curl -sL --max-time 5 "http://${domain}/" | tr -d '\0')"; then
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

    # Collate parked domains
    if [[ -f "parked_domains_${1}.tmp" ]]; then
        cat "parked_domains_${1}.tmp" >> parked_domains.tmp
    fi
}

# Function 'log_event' logs domain processing events into the domain log.
# $1: domains to log stored in a variable
# $2: event type (dead, whitelisted, etc.)
# $3: source
log_event() {
    printf "%s\n" "$1" | awk -v type="$2" -v source="$3" -v time="$(date -u +"%H:%M:%S %d-%m-%y")" \
        '{print time "," type "," $0 "," source}' >> "$DOMAIN_LOG"
}

# Function 'format_file' calls a shell wrapper to
# standardize the format of a file.
# $1: file to format
format_file() {
    bash functions/tools.sh format "$1"
}

cleanup() {
    find . -maxdepth 1 -type f -name "*.tmp" -delete
    find . -maxdepth 1 -type f -name "x??" -delete

    # Prune old entries from parked domains file
    if (( $(wc -l < "$PARKED_DOMAINS") > 4000 )); then
        sed -i '1,100d' "$PARKED_DOMAINS"
    fi
}

trap cleanup EXIT

main

#!/bin/bash
# This script checks for parked and unparked domains and
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
    update_light_file

    # Cache parked domains (skip processing parked domains through unparked check)
    cat parked_domains.tmp >> "$PARKED_DOMAINS"
    format_file "$PARKED_DOMAINS"
}

remove_parked_domains() {
    printf "\n[start] Analyzing %s entries for parked domains\n" "$(wc -l < "$RAW")"

    # Split raw file into 12 equal files
    split -d -l $(($(wc -l < "$RAW")/12)) "$RAW"
    check_parked "x00" & check_parked "x01" &
    check_parked "x02" & check_parked "x03" &
    check_parked "x04" & check_parked "x05" &
    check_parked "x06" & check_parked "x07" &
    check_parked "x08" & check_parked "x09" &
    check_parked "x10" & check_parked "x11" &
    check_parked "x12" & check_parked "x13"
    wait
    [[ ! -f parked_domains.tmp ]] && return

    format_file parked_domains.tmp

    # Remove parked domains from raw file
    comm -23 "$RAW" parked_domains.tmp > raw.tmp && mv raw.tmp "$RAW"

    log_event "$(<parked_domains.tmp)" "parked" "raw"

    # Reset split files before next run
    find . -maxdepth 1 -type f -name "x??" -delete
}

add_unparked_domains() {
    printf "\n[start] Analyzing %s entries for unparked domains\n" "$(wc -l < "$RAW")"

    # Split raw file into 12 equal files
    split -d -l $(($(wc -l < "$PARKED_DOMAINS")/12)) "$PARKED_DOMAINS"
    check_unparked "x00" & check_unparked "x01" &
    check_unparked "x02" & check_unparked "x03" &
    check_unparked "x04" & check_unparked "x05" &
    check_unparked "x06" & check_unparked "x07" &
    check_unparked "x08" & check_unparked "x09" &
    check_unparked "x10" & check_unparked "x11" &
    check_unparked "x12" & check_unparked "x13"
    wait
    [[ ! -f unparked_domains.tmp ]] && return

    format_file unparked_domains.tmp

    # Remove unparked domains from parked domains file (parked domains file is unsorted)
    grep -vxFf unparked_domains.tmp "$PARKED_DOMAINS" > parked.tmp
    mv parked.tmp "$PARKED_DOMAINS"

    # Add unparked domains to raw file
    cat unparked_domains.tmp >> "$RAW"
    format_file "$RAW"

    log_event "$(<unparked_domains.tmp)" "unparked" "PARKED_DOMAINS"

    # Reset split files before next run
    find . -maxdepth 1 -type f -name "x??" -delete
}

check_parked() {
    [[ ! -f "$1" ]] && return

    # Track progress for first split file
    if [[ "$1" == 'x00' ]]; then
        local track=true
        local count=1
    fi

    while read -r domain; do
        # Check for parked message in site's HTML
        if grep -qiFf "$PARKED_TERMS" \
            <<< "$(curl -sL --max-time 2 "http://${domain}/" | tr -d '\0')"; then
            printf "[info] Found parked domain: %s\n" "$domain"
            printf "%s\n" "$domain" >> "parked_domains_${1}.tmp"
        fi

        # Track progress for first split file
        if [[ "$track" == true ]]; then
            (( count % 100 == 0 )) &&
                printf "[info] Analyzed %s%% of domains\n" "$((count * 100 / $(wc -l < "$1")))"
            (( count++ ))
        fi
    done < "$1"

    # Collate parked domains
    [[ -f "parked_domains_${1}.tmp" ]] &&
        cat "parked_domains_${1}.tmp" >> parked_domains.tmp
}

check_unparked() {
    [[ ! -f "$1" ]] && return

    # Track progress for first split file
    if [[ "$1" == 'x00' ]]; then
        local track=true
        local count=1
    fi

    while read -r domain; do
        # Check for parked message in site's HTML
        if ! grep -qiFf "$PARKED_TERMS" \
            <<< "$(curl -sL --max-time 5 "http://${domain}/" | tr -d '\0')"; then
            printf "[info] Found unparked domain: %s\n" "$domain"
            printf "%s\n" "$domain" >> "unparked_domains_${1}.tmp"
        fi

        # Track progress for first split file
        if [[ "$track" == true ]]; then
            (( count % 100 == 0 )) &&
                printf "[info] Analyzed %s%% of domains\n" "$((count * 100 / $(wc -l < "$1")))"
            (( count++ ))
        fi
    done < "$1"

    # Collate unparked domains
    [[ -f "unparked_domains_${1}.tmp" ]] &&
        cat "unparked_domains_${1}.tmp" >> unparked_domains.tmp
}

# Function 'update_light_file' removes any domains from the light raw file that
# are not found in the full raw file.
update_light_file() {
    comm -12 "$RAW" "$RAW_LIGHT" > light.tmp && mv light.tmp "$RAW_LIGHT"
}

# Function 'prune_parked_domains_file' removes old entries once the file reaches
# a threshold of entries.
prune_parked_domains_file() {
    [[ $(wc -l < "$PARKED_DOMAINS") -gt 4000 ]] && sed -i '1,100d' "$PARKED_DOMAINS"
    true
}

# Function 'log_event' logs domain processing events into the domain log.
# $1: domains to log stored in a variable
# $2: event type (dead, whitelisted, etc.)
# $3: source
log_event() {
    printf "%s\n" "$1" | awk -v type="$2" -v source="$3" -v time="$(date -u +"%H:%M:%S %d-%m-%y")" \
        '{print time "," type "," $0 "," source}' >> "$DOMAIN_LOG"
}

# Function 'format_file' is a shell wrapper to standardize the format of a file.
# $1: file to format
format_file() {
    bash functions/tools.sh format "$1"
}

cleanup() {
    find . -maxdepth 1 -type f -name "*.tmp" -delete
    find . -maxdepth 1 -type f -name "x??" -delete
    prune_parked_domains_file
}

trap cleanup EXIT
main

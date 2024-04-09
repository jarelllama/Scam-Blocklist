#!/bin/bash

# Checks for parked/unparked domains and removes/adds them accordingly.
# Latest code review: 9 April 2024

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly PARKED_TERMS='config/parked_terms.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'

main() {
    # Format files
    for file in config/* data/*; do
        format_file "$file"
    done

    check_parked
    check_unparked

    # Cache parked domains to be used as a filter for newly retrieved domains
    # (done last to skip unparked check)
    sort -u parked_cache.tmp "$PARKED_DOMAINS" -o "$PARKED_DOMAINS"
}

# Function 'check_parked' removes parked domains from the raw file, raw light
# file, and subdomains file.
check_parked() {
    # Include domains with subdomains in parked check. It is assumed that if
    # the subdomain is parked, so is the root domain. For this reason, the
    # root domains are excluded to not waste processing time
    comm -23 <(sort "$RAW" "$SUBDOMAINS") "$ROOT_DOMAINS" > domains.tmp

    find_parked_in domains.tmp || return

    # Copy temporary parked file to be added into parked cache later
    # This parked cache includes subdomains
    cp parked.tmp parked_cache.tmp

    remove_parked_from "$SUBDOMAINS"

   # Strip subdomains from parked domains
    while read -r subdomain; do
        sed "s/^${subdomain}\.//" parked.tmp | sort -u -o parked.tmp
    done < "$SUBDOMAINS_TO_REMOVE"

    remove_parked_from "$RAW"
    remove_parked_from "$RAW_LIGHT"
    remove_parked_from "$ROOT_DOMAINS"

    log_event "$(<parked.tmp)" parked raw
}

# Function 'check_unparked' finds unparked domains in the parked domains file
# (also called the parked domains cache) and adds them back into the raw file.
#
# Note that unparked domains are not added back into the raw light file due
# to limitations in the way the parked domains are recorded.
check_unparked() {
    find_parked_in "$PARKED_DOMAINS"
    # No need to return if no parked domains found

    # Get unparked domains
    # (parked domains files need to be sorted here)
    comm -23 <(sort "$PARKED_DOMAINS") <(sort parked.tmp) > unparked.tmp

    [[ ! -s unparked.tmp ]] && return

    # Include only parked domains in parked domains file
    # grep is used here because the 'find_parked_in' function messes with the
    # order of the entries
    grep -xFf parked.tmp "$PARKED_DOMAINS" > temp
    mv temp "$PARKED_DOMAINS"

    # Add unparked domains to raw file
    # Note unparked subdomains are added back too and will be processed by the
    # validation check outside of this script
    sort -u unparked.tmp "$RAW" -o "$RAW"

    log_event "$(<unparked.tmp)" unparked parked_domains_file
}

# Function 'find_parked_in' efficiently checks for parked domains from a given
# file by running the checks in parallel.
# Input:
#   $1: file to process
# Output:
#   parked.tmp
#   return 1 (if parked domains not found)
find_parked_in() {
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
    cat parked_domains_x??.tmp >> parked.tmp 2> /dev/null
    rm parked_domains_x??.tmp 2> /dev/null

    format_file parked.tmp

    printf "[success] Found %s parked domains\n" "$(wc -l < parked.tmp)"

    # Return 1 if no parked domains were found
    [[ ! -s parked.tmp ]] && return 1 || return
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
        # Note <(curl... | tr...) outputs a broken pipe error
        # tr used here to remove null characters which some sites seem to have
        if grep -qiFf "$PARKED_TERMS" <<< "$(curl -sL --max-time 3 "http://${domain}/" \
            | tr -d '\0')"; then
            printf "[info] Found parked domain: %s\n" "$domain"
            printf "%s\n" "$domain" >> "parked_domains_${1}.tmp"
        fi

        # Skip progress tracking if not first split file
        [[ "$track" != true ]] && continue

        if (( count % 100 == 0 )); then
            printf "[info] Analyzed %s%% of domains\n" \
                "$(( count * 100 / $(wc -l < "$1") ))"
        fi

        (( count++ ))
    done < "$1"
}

# Function 'remove_parked_from' removes parked domains from the given file.
# The parked.tmp file should be present before running.
# Input:
#   $1: file to remove parked domains from
remove_parked_from() {
    comm -23 <(sort "$1") parked.tmp > temp
    mv temp "$1"
}

# Function 'log_event' calls a shell wrapper to log domain processing events
# into the domain log.
#   $1: domains to log stored in a variable
#   $2: event type (dead, whitelisted, etc.)
#   $3: source
log_event() {
    bash functions/tools.sh log_event "$1" "$2" "$3"
}

# Function 'format_file' calls a shell wrapper to standardize the format
# of a file.
#   $1: file to format
format_file() {
    bash functions/tools.sh format "$1"
}

cleanup() {
    find . -maxdepth 1 -type f -name "*.tmp" -delete
    find . -maxdepth 1 -type f -name "x??" -delete

    # Prune old entries from parked domains file
    lines="$(wc -l < "$PARKED_DOMAINS")"
    max=5000
    if (( lines > max )); then
        sed -i "1,$(( lines - max ))d" "$PARKED_DOMAINS"
    fi
}

trap cleanup EXIT

main

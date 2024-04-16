#!/bin/bash

# Checks for parked/unparked domains and removes/adds them accordingly.

readonly FUNCTION='bash functions/tools.sh'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly PARKED_TERMS='config/parked_terms.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'

main() {
    check_parked
    check_unparked

    if [[ -f parked_cache.tmp ]]; then
        # Cache parked domains to be used as a filter for newly retrieved
        # domains (done last to skip unparked check)
        # Note the parked domains file should remain unsorted
        cat parked_cache.tmp >> "$PARKED_DOMAINS"
    fi
}

# Function 'check_parked' removes parked domains from the raw file, raw light
# file, and subdomains file.
check_parked() {
    # Include subdomains in the parked check. It is assumed that if the
    # subdomain is parked, so is the root domain. For this reason, the root
    # domains are excluded to not waste processing time.
    comm -23 <(sort "$RAW" "$SUBDOMAINS") "$ROOT_DOMAINS" > domains.tmp

    find_parked_in domains.tmp || return

    # Copy temporary parked file to be added into parked cache later
    # This parked cache includes subdomains
    cp parked.tmp parked_cache.tmp

    # Remove parked domains from subdomains file
    comm -23 "$SUBDOMAINS" parked.tmp > temp
    mv temp "$SUBDOMAINS"

    # Strip subdomains from parked domains
    while read -r subdomain; do
        sed -i "s/^${subdomain}\.//" parked.tmp
    done < "$SUBDOMAINS_TO_REMOVE"
    sort -u parked.tmp -o parked.tmp

    # Remove parked domains from the various files
    for file in "$RAW" "$RAW_LIGHT" "$ROOT_DOMAINS"; do
        comm -23 "$file" parked.tmp > temp
        mv temp "$file"
    done

    # Call shell wrapper to log parked domains into domain log
    $FUNCTION --log-domains parked.tmp parked raw
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
    comm -23 <(sort "$PARKED_DOMAINS") parked.tmp > unparked.tmp

    [[ ! -s unparked.tmp ]] && return

    # Include only parked domains in parked domains file
    # grep is used here because the parked domains file is unsorted
    grep -xFf parked.tmp "$PARKED_DOMAINS" > temp
    mv temp "$PARKED_DOMAINS"

    # Add unparked domains to raw file
    # Note that unparked subdomains are added back too and will be processed by
    # the validation check outside of this script.
    sort -u unparked.tmp "$RAW" -o "$RAW"

    # Call shell wrapper to log unparked domains into domain log
    $FUNCTION --log-domains unparked.tmp unparked parked_domains_file
}

# Function 'find_parked_in' efficiently checks for parked domains in a given
# file by running the checks in parallel.
# Input:
#   $1: file to process
# Output:
#   parked.tmp
#   return 1 (if parked domains not found)
find_parked_in() {
    local execution_time
    execution_time="$(date +%s)"

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
    cat parked_domains_x??.tmp > parked.tmp 2> /dev/null
    rm parked_domains_x??.tmp 2> /dev/null

    sort -u parked.tmp -o parked.tmp

    printf "[success] Found %s parked domains\n" "$(wc -l < parked.tmp)"
    printf "Processing time: %s second(s)\n" "$(( $(date +%s) - execution_time ))"

    # Return 1 if no parked domains were found
    [[ ! -s parked.tmp ]] && return 1 || return 0
}

# Function 'find_parked' queries sites in a given file for parked messages in
# their HTML.
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

    # Loop through domains
    while read -r domain; do
        # Check for parked messaged in the site's HTML (retry a max of 1 time)
        if grep -qiFf "$PARKED_TERMS" \
            <<< "$(curl -sL --max-time 3 --retry 1 --retry-all-errors \
            "http://${domain}/" | tr -d '\0')"
            # tr is used here to remove null characters found in some sites.
            then
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

cleanup() {
    find . -maxdepth 1 -type f -name "*.tmp" -delete
    find . -maxdepth 1 -type f -name "x??" -delete

    # Call shell wrapper to prune old entries from parked domains file
    $FUNCTION --prune-lines "$PARKED_DOMAINS" 7000
}

# Entry point

trap cleanup EXIT

$FUNCTION --format-all

main

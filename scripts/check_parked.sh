#!/bin/bash

# Check for parked/unparked domains and remove/add them accordingly.
# It should be noted that although the domain may be parked, subfolders of the
# domain may host malicious content. This script does not account for that.

readonly FUNCTION='bash scripts/tools.sh'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly PARKED_TERMS='config/parked_terms.txt'
readonly LOG_SIZE=75000

main() {
    # Split raw file into 2 parts for each parked check job
    if [[ "$1" == part? ]]; then
        split -d -l "$(( $(wc -l < "$RAW") / 2 ))" "$RAW"
        # Sometimes an x02 exists
        [[ -f x02 ]] && cat x02 >> x01
    fi

    # The parked check consists of multiple parts to get around the time limit
    # of Github jobs.
    case "$1" in
        checkunparked)
            # The unparked check being done in the workflow before the parked
            # check means the recently added unparked domains are processed by
            # the parked check while the recently added parked domains are not
            # processed by the unparked check.
            check_unparked
            ;;
        part1)
            check_parked x00
            ;;
        part2)
            check_parked x01
            ;;
        remove)
            remove_parked
            ;;
        *)
            error "Invalid argument passed: $1"
            ;;
    esac

    $FUNCTION --prune-lines "$PARKED_DOMAINS" "$LOG_SIZE"
}

# Find parked domains and collate them into the parked domains file to be
# removed later. The parked domains file is also used as a filter for newly
# retrieved domains.
# Input
#   $1: file to check for parked domains in
check_parked() {
    # Exclude parked already in the parked domains file but not yet removed
    comm -23 "$1" <(sort "$PARKED_DOMAINS") > domains.tmp

    find_parked_in domains.tmp

    # Save parked domains to be removed from the various files later
    # and to act as a filter for newly retrieved domains.
    # Note the parked domains file should remain unsorted.
    cat parked.tmp >> "$PARKED_DOMAINS"
}

# Find unparked domains in the parked domains file and add them back into the
# raw file. Note that unparked domains are not added back into the raw light
# file as the parked domains are not logged with their sources.
check_unparked() {
    find_parked_in "$PARKED_DOMAINS"

    # Assume domains that errored out during the check are still parked
    sort -u errored.tmp parked.tmp -o parked.tmp

    # Get unparked domains in parked domains file
    comm -23 <(sort "$PARKED_DOMAINS") parked.tmp > unparked_domains.tmp

    [[ ! -s unparked_domains.tmp ]] && return

    # Add unparked domains to raw file
    sort -u unparked_domains.tmp "$RAW" -o "$RAW"

    # Update parked domains file to only include parked domains
    mawk '
        NR==FNR {
            lines[$0]
            next
        } $0 in lines
    ' parked.tmp "$PARKED_DOMAINS" > temp
    mv temp "$PARKED_DOMAINS"

    # Call shell wrapper to log number of unparked domains in domain log
    $FUNCTION --log-domains "$(wc -l < unparked_domains.tmp)" unparked_count \
        parked_domains_file
}

# Efficiently check for parked domains in a given file by running the checks in
# parallel.
# Input:
#   $1: file to process
# Output:
#   parked.tmp
#   errored.tmp (consists of domains that errored during curl)
find_parked_in() {
    local execution_time
    execution_time="$(date +%s)"

    printf "\n[info] Processing file %s\n" "$1"
    printf "[start] Analyzing %s entries for parked domains\n" "$(wc -l < "$1")"

    # Split file into 17 equal files
    split -d -l "$(( $(wc -l < "$1") / 17 ))" "$1"
    # Sometimes an x19 exists
    [[ -f x19 ]] && cat x19 >> x18

    # Run checks in parallel
    find_parked x00 & find_parked x01 & find_parked x02 & find_parked x03 &
    find_parked x04 & find_parked x05 & find_parked x06 & find_parked x07 &
    find_parked x08 & find_parked x09 & find_parked x10 & find_parked x11 &
    find_parked x12 & find_parked x13 & find_parked x14 & find_parked x15 &
    find_parked x16 & find_parked x17 & find_parked x18
    wait

    # Create files to avoid not found errors
    touch parked_domains_xxx.tmp errored_domains_xxx.tmp

    # Collate parked domains and errored domains
    sort -u parked_domains_x??.tmp -o parked.tmp
    sort -u errored_domains_x??.tmp -o errored.tmp

    printf "[success] Found %s parked domains\n" "$(wc -l < parked.tmp) "
    printf "Processing time: %s second(s)\n" "$(( $(date +%s) - execution_time ))"
}

# Query sites in a given file for parked messages in their HTML.
# Input:
#   $1: file to process
# Output:
#   parked_domains_x??.tmp (if parked domains found)
#   errored_domains_x??.tmp (if any domains errored during curl)
find_parked() {
    [[ ! -f "$1" ]] && return

    local track count html

    # Track progress only for first split file
    if [[ "$1" == 'x00' ]]; then
        track=true
        count=1
    fi

    # Loop through domains
    while read -r domain; do
        if [[ "$track" == true ]]; then
            if (( count % 100 == 0 )); then
                printf "[progress] Analyzed %s%% of domains\n" \
                    "$(( count * 100 / $(wc -l < "$1") ))"
            fi

            (( count++ ))
        fi

        # Get the site's HTML and redirect stderror to stdout for error
        # checking later
        # tr is used here to remove null characters found in some sites
        # Appears that -k causes some domains to have an empty response, which
        # causes parked domains to seem unparked.
        html="$(curl -sSL --max-time 3 "https://${domain}/" 2>&1 | tr -d '\0')"

        # If using HTTPS fails, use HTTP
        if grep -qF 'curl: (60) SSL:' <<< "$html"; then
            html="$(curl -sSL --max-time 3 "http://${domain}/" 2>&1 \
                | tr -d '\0')"
        fi

        # Check for curl errors
        if grep -qF 'curl:' <<< "$html"; then
            # Collate domains that errored so they can be dealt with later
            # accordingly
            printf "%s\n" "$domain" >> "errored_domains_${1}.tmp"
            continue
        # Check for parked messages in the site's HTML
        elif grep -qiFf "$PARKED_TERMS" <<< "$html"; then
            printf "[info] Found parked domain: %s\n" "$domain"
            printf "%s\n" "$domain" >> "parked_domains_${1}.tmp"
        fi
    done < "$1"
}

# Remove parked domains from the raw file and raw light file.
remove_parked() {
    local count_before count_after parked_count

    count_before="$(wc -l < "$RAW")"

    sort -u "$PARKED_DOMAINS" -o parked.tmp

    # Remove dead domains from the raw file
    comm -23 "$RAW" parked.tmp > temp
    mv temp "$RAW"

    # Remove dead domains from the raw light file
    comm -23 "$RAW_LIGHT" parked.tmp > temp
    mv temp "$RAW_LIGHT"

    count_after="$(wc -l < "$RAW")"

    parked_count="$(( count_before - count_after ))"

    printf "\nRemoved parked domains from raw file.\nBefore: %s  Removed: %s  After: %s\n" \
    "$count_before" "$parked_count" "$count_after"

    # Call shell wrapper to log number of parked domains in domain log
    $FUNCTION --log-domains "$parked_count" parked_count raw
}

# Print error message and exit.
# Input:
#   $1: error message to print
error() {
    printf "\n\e[1;31m%s\e[0m\n\n" "$1" >&2
    exit 1
}

# Entry point

set -e

trap 'rm ./*.tmp temp x?? 2> /dev/null || true' EXIT

$FUNCTION --format-files

main "$1"

#!/bin/bash

# Check for parked or unparked domains and output them to respective files.
# Note that although the domain may be parked, subfolders of the domain may
# host malicious content. This script does not account for that.
# The parked check can be split into 2 parts to get around GitHub job timeouts.
# Input:
#   $1:
#     --check-unparked:       check for unparked domains in the given file
#     --check-parked:         check for parked domains in the given file
#     --check-parked-part-1:  check for parked domains in one half of the file
#     --check-parked-part-2:  check for parked domains in the other half of the
#                             file. should only be ran after part 1
#   $2:                file to process
#   parked_terms.txt:  list of parked terms to check for
# Output:
#   unparked_domains.txt (for unparked domains check)
#   parked_domains.txt (for parked domains check)

readonly ARGUMENT="$1"
readonly FILE="$2"
readonly PARKED_TERMS='parked_terms.txt'

main() {
    [[ ! -f "$FILE" ]] && error "File $FILE not found."
    [[ ! -s "$PARKED_TERMS" ]] && error 'Parked terms not found.'

    # Split the file into 2 parts for each GitHub job if requested
    if [[ "$ARGUMENT" == --check-parked-part-? ]]; then
        split -l "$(( $(wc -l < "$FILE") / 2 ))" "$FILE"
    fi

    case "$ARGUMENT" in
        --check-unparked)
            find_parked_in "$FILE"

            # Assume domains that errored out during the check are still parked
            comm -23 <(sort -u "$FILE") <(sort -u errored.tmp parked.tmp) \
                > unparked_domains.txt
            ;;

        --check-parked)
            find_parked_in "$FILE"
            sort -u parked.tmp -o parked_domains.txt
            ;;

        --check-parked-part-1)
            find_parked_in xaa
            sort -u parked.tmp -o parked_domains.txt
            ;;

        --check-parked-part-2)
            # Sometimes an xac exists
            [[ -f xac ]] && cat xac >> xab

            find_parked_in xab
            # Append the parked domains since the parked domains file
            # should contain parked domains from part 1.
            sort -u parked.tmp parked_domains.txt -o parked_domains.txt
            ;;

        *)
            error "Invalid argument passed: $ARGUMENT"
            ;;
    esac
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

    # Split the file into 17 equal files
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
    [[ ! -s "$1" ]] && return

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
        if grep -qF 'curl: (60)' <<< "$html"; then
            html="$(curl -sSL --max-time 3 "http://${domain}/" 2>&1 \
                | tr -d '\0')"
        fi

        # Check for curl errors
        if grep -qF 'curl:' <<< "$html"; then
            # Collate domains that errored so they can be dealt with later
            # accordingly
            printf "%s\n" "$domain" >> "errored_domains_${1}.tmp"

        # Check for parked messages in the site's HTML
        elif grep -qiFf "$PARKED_TERMS" <<< "$html"; then
            printf "[info] Found parked domain: %s\n" "$domain"
            printf "%s\n" "$domain" >> "parked_domains_${1}.tmp"
        fi
    done < "$1"
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

main "$1" "$2"

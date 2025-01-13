#!/bin/bash

# Checks for parked/unparked domains and removes/adds them accordingly.
# It should be noted that although the domain may be parked, subfolders of the
# domain may host malicious content. This script does not account for that.

readonly FUNCTION='bash scripts/tools.sh'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly PARKED_TERMS='config/parked_terms.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'
readonly LOG_SIZE=50000

main() {
    # Split raw file into 2 parts for each parked check job
    if [[ "$1" == part? ]]; then
        split -d -l $(( $(wc -l < "$RAW") / 2 )) "$RAW"
    fi

    case "$1" in
        'checkunparked')
            # The unparked check being done in the workflow before the parked
            # check means the recently added unparked domains are processed by
            # the parked check while the recently added parked domains are not
            # processed by the unparked check.
            check_unparked
            ;;
        'part1')
            check_parked x00
            ;;
        'part2')
            # Sometimes an x02 exists
            [[ -f x02 ]] && cat x02 >> x01
            check_parked x01
            ;;
        'remove')
            remove_parked
            ;;
        *)
            printf "\n\e[1;31mNo argument passed.\e[0m\n\n"
            exit 1
            ;;
    esac
}

# Function 'check_parked' finds parked domains and collates them into the
# parked domains file to be removed from the various files later. The parked
# domains file is also used as a filter for newly retrieved domains.
check_parked() {
    # Include subdomains found in the given file. It is assumed that if the
    # subdomain is parked, so is the root domain. For this reason, the root
    # domains are excluded to not waste processing time.
    comm -23 <(sort <(grep -f "$1" "$SUBDOMAINS") "$1") "$ROOT_DOMAINS" \
        > domains.tmp

    find_parked_in domains.tmp

    # Save parked domains to be removed from the various files later
    # and to act as a filter for newly retrieved domains.
    # Note the parked domains file should remain unsorted.
    cat parked.tmp >> "$PARKED_DOMAINS"
}

# Function 'check_unparked' finds unparked domains in the parked domains file
# and adds them back into the raw file.
#
# Note that unparked domains are not added back into the raw light file as
# the parked domains are not logged with their sources.
check_unparked() {
    find_parked_in "$PARKED_DOMAINS"

    # Assume domains that errored out during the check are still parked
    sort -u errored.tmp parked.tmp -o parked.tmp

    # Get unparked domains in parked domains file
    comm -23 <(sort "$PARKED_DOMAINS") parked.tmp > unparked_domains.tmp

    [[ ! -s unparked_domains.tmp ]] && return

    # Update parked domains file to only include parked domains
    # grep is used here because the parked domains file is unsorted
    grep -xFf parked.tmp "$PARKED_DOMAINS" > temp
    mv temp "$PARKED_DOMAINS"

    # Add unparked domains to raw file
    # Note that unparked subdomains are added back too and will be processed by
    # the validation check outside of this script.
    sort -u unparked_domains.tmp "$RAW" -o "$RAW"

    # Call shell wrapper to log number of unparked domains in domain log
    $FUNCTION --log-domains "$(wc -l < unparked_domains.tmp)" unparked_count parked_domains_file
}

# Function 'find_parked_in' efficiently checks for parked domains in a given
# file by running the checks in parallel.
# Input:
#   $1: file to process
# Output:
#   parked.tmp
#   errored.tmp (consists of domains that errored during curl)
find_parked_in() {
    local execution_time
    execution_time="$(date +%s)"

    # Always create parked.tmp file to avoid not found errors
    touch parked.tmp

    printf "\n[info] Processing file %s\n" "$1"
    printf "[start] Analyzing %s entries for parked domains\n" "$(wc -l < "$1")"

    # Split file into 17 equal files
    split -d -l $(( $(wc -l < "$1") / 17 )) "$1"
    # Sometimes an x19 exists
    [[ -f x19 ]] && cat x19 >> x18

    # Run checks in parallel
    find_parked x00 & find_parked x01 & find_parked x02 & find_parked x03 &
    find_parked x04 & find_parked x05 & find_parked x06 & find_parked x07 &
    find_parked x08 & find_parked x09 & find_parked x10 & find_parked x11 &
    find_parked x12 & find_parked x13 & find_parked x14 & find_parked x15 &
    find_parked x16 & find_parked x17 & find_parked x18
    wait

    # Collate parked domains and errored domains (ignore not found errors)
    sort -u parked_domains_x??.tmp -o parked.tmp 2> /dev/null
    sort -u errored_domains_x??.tmp -o errored.tmp 2> /dev/null

    rm ./*x??.tmp

    printf "[success] Found %s parked domains\n" "$(wc -l < parked.tmp) "
    printf "Processing time: %s second(s)\n" "$(( $(date +%s) - execution_time ))"
}

# Function 'find_parked' queries sites in a given file for parked messages in
# their HTML.
# Input:
#   $1: file to process
# Output:
#   parked_domains_x??.tmp (if parked domains found)
#   errored_domains_x??.tmp (if any domains errored during curl)
find_parked() {
    [[ ! -f "$1" ]] && return

    # Track progress only for first split file
    if [[ "$1" == 'x00' ]]; then
        local track=true
        local count=1
        local lines
        lines="$(wc -l < "$1")"
    fi

    # Loop through domains
    while read -r domain; do
        if [[ "$track" == true ]]; then
            if (( count % 100 == 0 )); then
                printf "[progress] Analyzed %s%% of domains\n" \
                    "$(( count * 100 / lines ))"
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

        # Check for curl errors
        elif grep -qF 'curl:' <<< "$html"; then
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

# Function 'remove_parked' removes parked domains from the raw file, raw light
# file, root domains file and subdomains file.
remove_parked() {
    count_before="$(wc -l < "$RAW")"

    sort -u "$PARKED_DOMAINS" -o parked.tmp

    # Remove parked domains from subdomains file
    comm -23 "$SUBDOMAINS" parked.tmp > temp
    mv temp "$SUBDOMAINS"

    # Strip subdomains from parked domains
    gawk '
        # store lines from subdomains_to_remove as keys in array "dom"
        NR==FNR { dom[$0]; next }
        # process parked.tmp
        {
            # split current line by "." and store strings in array "arr"
            n=split($0,arr,".")
            # if "arr" has more than 1 element,
            # and string in "dom" matches 1st element of array "arr", remove subdomain from the line
            if (n>1 && arr[1] in dom) {
                regex="^" arr[1] "."
                sub(regex,"")
            }
            # print out the line
            print $0
        }
    ' "$SUBDOMAINS_TO_REMOVE" parked.tmp |
    sort -u > parked-removed-subdomains.tmp

    mv parked-removed-subdomains.tmp parked.tmp

    # Remove parked domains from the various files
    for file in "$RAW" "$RAW_LIGHT" "$ROOT_DOMAINS"; do
        comm -23 "$file" parked.tmp > temp
        mv temp "$file"
    done

    count_after="$(wc -l < "$RAW")"

    parked_count="$(( count_before - count_after ))"

    printf "\nRemoved parked domains from raw file.\nBefore: %s  Removed: %s  After: %s\n" \
    "$count_before" "$parked_count" "$count_after"

    # Call shell wrapper to log number of parked domains in domain log
    $FUNCTION --log-domains "$parked_count" parked_count raw
}

cleanup() {
    find . -maxdepth 1 -type f -name "*.tmp" -delete
    find . -maxdepth 1 -type f -name "x??" -delete

    # Call shell wrapper to prune old entries from parked domains file
    $FUNCTION --prune-lines "$PARKED_DOMAINS" "$LOG_SIZE"
}

# Entry point

command -v "gawk" 1>/dev/null || {
    echo "Error: gawk not found." >&2
    exit 1
}

trap cleanup EXIT

$FUNCTION --format-all

main "$1"

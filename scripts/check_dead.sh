#!/bin/bash

# Check for dead/resurrected domains and remove/add them accordingly.

readonly FUNCTION='bash scripts/tools.sh'
readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly LOG_SIZE=75000

main() {
    # Install AdGuard's Dead Domains Linter
    if ! command -v dead-domains-linter &> /dev/null; then
        npm install -g @adguard/dead-domains-linter > /dev/null
    fi

    # Split raw file into 2 parts for each dead check job
    if [[ "$1" == part? ]]; then
        split -d -l "$(( $(wc -l < "$RAW") / 2 ))" "$RAW"
    fi

    # The dead check consists of multiple parts to get around the time limit of
    # Github jobs.
    case "$1" in
        checkalive)
            # The alive check being done in the workflow before the dead check
            # means the recently added resurrected domains are processed by the
            # dead check while the recently added dead domains are not
            # processed by the alive check.
            check_alive
            ;;
        part1)
            check_dead x00
            ;;
        part2)
            # Sometimes an x02 exists
            [[ -f x02 ]] && cat x02 >> x01
            check_dead x01
            ;;
        remove)
            remove_dead
            ;;
        *)
            error "Invalid argument passed: $1"
            ;;
    esac

    $FUNCTION --prune-lines "$DEAD_DOMAINS" "$LOG_SIZE"
}

# Find dead domains and collate them into the dead domains file to be removed
# later. The dead domains file is also used as a filter for newly retrieved
# domains.
# Input:
#   $1: file to check for dead domains in
check_dead() {
    # Exclude domains already in the dead domains file but not yet removed
    comm -23 "$1" <(sort "$DEAD_DOMAINS") > domains.tmp

    find_dead_in domains.tmp

    # Save dead domains to be removed from the various files later
    # and to act as a filter for newly retrieved domains.
    # Note the dead domains file should remain unsorted.
    cat dead.tmp >> "$DEAD_DOMAINS"
}

# Find resurrected domains in the dead domains file and add them back into the
# raw file. Note that resurrected domains are not added back into the raw light
# file as the dead domains are not logged with their sources.
check_alive() {
    find_dead_in "$DEAD_DOMAINS"

    # Get resurrected domains in dead domains file
    comm -23 <(sort "$DEAD_DOMAINS") dead.tmp > alive_domains.tmp

    [[ ! -s alive_domains.tmp ]] && return

    # Add resurrected domains to raw file
    sort -u alive_domains.tmp "$RAW" -o "$RAW"

    # Update dead domains file to only include dead domains
    mawk '
        NR==FNR {
            lines[$0]
            next
        } $0 in lines
    ' dead.tmp "$DEAD_DOMAINS" > temp
    mv temp "$DEAD_DOMAINS"

    # Call shell wrapper to log number of resurrected domains in domain log
    $FUNCTION --log-domains "$(wc -l < alive_domains.tmp)" resurrected_count\
        dead_domains_file
}

# Efficiently check for dead domains in a given file by running the checks in
# parallel.
# Input:
#   $1: file to process
# Output:
#   dead.tmp
find_dead_in() {
    local execution_time
    execution_time="$(date +%s)"

    printf "\n[info] Processing file %s\n" "$1"
    printf "[start] Analyzing %s entries for dead domains\n" "$(wc -l < "$1")"

    # Split file into 2 equal parts
    split -d -l "$(( $(wc -l < "$1") / 2 ))" "$1"
    # Sometimes an x02 exists
    [[ -f x02 ]] && cat x02 >> x01

    # Run checks in parallel
    find_dead x00 & find_dead x01
    wait

    sort -u dead_domains_x??.tmp -o dead.tmp

    printf "[success] Found %s dead domains\n" "$(wc -l < dead.tmp) "
    printf "Processing time: %s second(s)\n" "$(( $(date +%s) - execution_time ))"
}

# Find dead domains in a given file by formatting the file and then processing
# it through AdGuard's Dead Domains Linter.
# Input:
#   $1: file to process
# Output:
#   dead_domains_x??.tmp
find_dead() {
    [[ ! -f "$1" ]] && return

    # Format to Adblock Plus syntax for Dead Domains Linter
    # Use variable filename to avoid filename clashes
    mawk '{ print "||" $0 "^" }' "$1" > "${1}.tmp"

    dead-domains-linter -i "${1}.tmp" --export "dead_domains_${1}.tmp"
}

# Remove dead domains from the raw file and raw light file.
remove_dead() {
    local count_before count_after dead_count

    count_before="$(wc -l < "$RAW")"

    sort -u "$DEAD_DOMAINS" -o dead.tmp

    # Remove dead domains from the raw file
    comm -23 "$RAW" dead.tmp > temp
    mv temp "$RAW"

    # Remove dead domains from the raw light file
    comm -23 "$RAW_LIGHT" dead.tmp > temp
    mv temp "$RAW_LIGHT"

    count_after="$(wc -l < "$RAW")"

    dead_count="$(( count_before - count_after ))"

    printf "\nRemoved dead domains from raw file.\nBefore: %s  Removed: %s  After: %s\n" \
    "$count_before" "$dead_count" "$count_after"

    # Call shell wrapper to log number of dead domains in domain log
    $FUNCTION --log-domains "$dead_count" dead_count raw
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
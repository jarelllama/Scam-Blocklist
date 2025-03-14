#!/bin/bash

# Check for dead or resurrected domains and output them to respective files.
# The dead check can be split into 2 parts to get around GitHub job timeouts.
# Input:
#   $1:
#     --check-alive:        check for resurrected domains in the given file
#     --check-dead:         check for dead domains in the given file
#     --check-dead-part-1:  check for dead domains in one half of the file
#     --check-dead-part-2:  check for dead domains in the other half of the
#                           file. should only be ran after part 1
#   $2: file to process
# Output:
#   alive_domains.txt, for resurrected domains check
#   dead_domains.txt, for dead domains check

readonly ARGUMENT="$1"
readonly FILE="$2"

main() {
    [[ ! -f "$FILE" ]] && error "File $FILE not found"

    # Install AdGuard's Dead Domains Linter
    if ! command -v dead-domains-linter &> /dev/null; then
        npm install -g @adguard/dead-domains-linter > /dev/null
    fi

    # Split the file into 2 parts for each GitHub job if requested
    if [[ "$ARGUMENT" == --check-dead-part-? ]]; then
        split -d -l "$(( $(wc -l < "$FILE") / 2 ))" "$FILE"
    fi

    case "$ARGUMENT" in
        --check-alive)
            find_dead_in "$FILE"
            comm -23 <(sort -u "$FILE") dead.tmp > alive_domains.txt
            ;;

        --check-dead)
            find_dead_in "$FILE"
            sort -u dead.tmp -o dead_domains.txt
            ;;

        --check-dead-part-1)
            find_dead_in x00
            sort -u dead.tmp -o dead_domains.txt
            ;;

        --check-dead-part-2)
            # Sometimes an x02 exists
            [[ -f x02 ]] && cat x02 >> x01

            find_dead_in x01
            # Append the dead domains since the dead domains file
            # should contain dead domains from part 1.
            sort -u dead.tmp dead_domains.txt -o dead_domains.txt
            ;;

        *)
            error "Invalid argument passed: $ARGUMENT"
            ;;
    esac
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

    # Split the file into 2 equal parts
    split -l "$(( $(wc -l < "$1") / 2 ))" "$1"
    # Sometimes an xac exists
    [[ -f xac ]] && cat xac >> xab

    # Run checks in parallel
    find_dead xaa & find_dead xab
    wait

    sort -u dead_x??.tmp -o dead.tmp

    printf "[success] Found %s dead domains\n" "$(wc -l < dead.tmp) "
    printf "Processing time: %s second(s)\n" "$(( $(date +%s) - execution_time ))"
}

# Find dead domains in a given file by formatting the file and then processing
# it through AdGuard's Dead Domains Linter.
# Input:
#   $1: file to process
# Output:
#   dead_x??.tmp
find_dead() {
    [[ ! -s "$1" ]] && return

    # Format to Adblock Plus syntax for Dead Domains Linter
    # Use a variable filename to avoid filename clashes
    mawk '{ print "||" $0 "^" }' "$1" > "${1}.tmp"

    dead-domains-linter -i "${1}.tmp" --export "dead_${1}.tmp"
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

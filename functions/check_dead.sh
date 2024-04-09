#!/bin/bash

# Checks for dead/resurrected domains and removes/adds them accordingly.
# Latest code review: 9 April 2024

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'

main() {
    # Install AdGuard's Dead Domains Linter
    npm install -g @adguard/dead-domains-linter > /dev/null

    # Format files
    for file in config/* data/*; do
        bash functions/tools.sh format "$file"
    done

    check_dead
    check_alive

    # Cache dead domains to be used as a filter for newly retrieved domains
    # (done last to skip alive check)
    if [[ -f dead_cache.tmp ]]; then
        sort -u dead_cache.tmp "$DEAD_DOMAINS" -o "$DEAD_DOMAINS"
    fi
}

# Function 'check_dead' removes dead domains from the raw file, raw light file,
# and subdomains file.
check_dead() {
    # Include domains with subdomains in dead check. Exclude the root domains
    # since the subdomains were what was retrieved during domain retrieval
    comm -23 <(sort "$RAW" "$SUBDOMAINS") "$ROOT_DOMAINS" > domains.tmp

    find_dead_in domains.tmp || return

    # Copy temporary dead file to be added into dead cache later
    # This dead cache includes subdomains
    cp dead.tmp dead_cache.tmp

    remove_dead_from "$SUBDOMAINS"

    # Strip subdomains from dead domains
    while read -r subdomain; do
        sed -i "s/^${subdomain}\.//" dead.tmp
    done < "$SUBDOMAINS_TO_REMOVE"
    sort -u dead.tmp -o dead.tmp

    # Remove dead domains from the various files
    for file in "$RAW" "$RAW_LIGHT" "$ROOT_DOMAINS"; do
        comm -23 "$file" dead.tmp > temp
        mv temp "$file"
    done

    log_event "$(<dead.tmp)" dead raw
}

# Function 'check_alive' finds resurrected domains in the dead domains file
# (also called the dead domains cache) and adds them back into the raw file.
#
# Note that resurrected domains are not added back into the raw light file due
# to limitations in the way the dead domains are recorded.
check_alive() {
    find_dead_in "$DEAD_DOMAINS"  # No need to return if no dead domains found

    # Get resurrected domains in dead domains file
    # (dead domain file is unsorted)
    comm -23 <(sort "$DEAD_DOMAINS") dead.tmp > alive.tmp

    [[ ! -s alive.tmp ]] && return

    # Update dead domains file to only include dead domains
    # grep is used here because the dead domains file is unsorted
    grep -xFf dead.tmp "$DEAD_DOMAINS" > temp
    mv temp "$DEAD_DOMAINS"

    # Add resurrected domains to raw file
    # Note resurrected subdomains are added back too and will be processed by
    # the validation check outside of this script
    sort -u alive.tmp "$RAW" -o "$RAW"

    log_event "$(<alive.tmp)" resurrected dead_domains_file
}

# Function 'find_dead_in' finds dead domains in a given file by first formatting
# the file and then processing it through AdGuard's Dead Domains Linter.
# Input:
#   $1: file to process
# Output:
#   dead.tmp
#   return 1 (if dead domains not found)
find_dead_in() {
    local temp
    temp="$(basename "$1").tmp"

    # Format to Adblock Plus syntax
    sed 's/.*/||&^/' "$1" > "$temp"

    dead-domains-linter -i "$temp" --export dead.tmp
    printf "\n"

    sort -u dead.tmp -o dead.tmp

    # Return 1 if no dead domains were found
    [[ ! -s dead.tmp ]] && return 1 || return 0
}

# Function 'log_event' calls a shell wrapper to log domain processing events
# into the domain log.
#   $1: domains to log stored in a variable
#   $2: event type (dead, whitelisted, etc.)
#   $3: source
log_event() {
    bash functions/tools.sh log_event "$1" "$2" "$3"
}

cleanup() {
    find . -maxdepth 1 -type f -name "*.tmp" -delete

    # Prune old entries from dead domains file
    bash functions/tools.sh prune_lines "$DEAD_DOMAINS" 6000
}

# Entry point

trap cleanup EXIT

main

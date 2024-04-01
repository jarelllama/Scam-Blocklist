#!/bin/bash

# Checks for dead/resurrected domains and removes/adds them accordingly.

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'
readonly WILDCARDS='data/wildcards.txt'
readonly REDUNDANT_DOMAINS='data/redundant_domains.txt'
readonly DOMAIN_LOG='config/domain_log.csv'

main() {
    # Install AdGuard's Dead Domains Linter
    npm i -g @adguard/dead-domains-linter

    for file in config/* data/*; do
        format_file "$file"
    done

    check_subdomains
    check_redundant
    check_dead
    check_alive

    # Remove domains from light raw file that are not found in full raw file
    comm -12 "$RAW" "$RAW_LIGHT" > light.tmp
    mv light.tmp "$RAW_LIGHT"

    # Cache dead domains (done last to skip alive domains check)
    cat dead_in_raw.tmp >> "$DEAD_DOMAINS"
    format_file "$DEAD_DOMAINS"
}

check_subdomains() {
    find_dead "$SUBDOMAINS" || return

    # Remove domains from subdomains file
    comm -23 "$SUBDOMAINS" dead.tmp > subdomains.tmp
    mv subdomains.tmp "$SUBDOMAINS"

    # Cache dead domains to filter out from newly retrieved domains
    cat dead.tmp >> "$DEAD_DOMAINS"
    format_file "$DEAD_DOMAINS"

    # Strip dead domains to their root domains
    while read -r subdomain; do
        dead_root_domains="$(sed "s/^${subdomain}\.//" dead.tmp | sort -u)"
    done < "$SUBDOMAINS_TO_REMOVE"

    # Remove dead root domains from raw file and root domains file
    comm -23 "$RAW" <(printf "%s" "$dead_root_domains") > raw.tmp
    comm -23 "$ROOT_DOMAINS" <(printf "%s" "$dead_root_domains") > root.tmp
    mv raw.tmp "$RAW"
    mv root.tmp "$ROOT_DOMAINS"

    log_event "$dead_root_domains" dead raw
}

check_redundant() {
    find_dead "$REDUNDANT_DOMAINS" || return

    # Remove dead domains from redundant domains file
    comm -23 "$REDUNDANT_DOMAINS" dead.tmp > redundant.tmp
    mv redundant.tmp "$REDUNDANT_DOMAINS"

    # Cache dead domains to filter out from newly retrieved domains
    cat dead.tmp >> "$DEAD_DOMAINS"
    format_file "$DEAD_DOMAINS"

    # Find unused wildcard
    while read -r wildcard; do
        # If no matches, consider wildcard as unused/dead
        if ! grep -q "\.${wildcard}$" "$REDUNDANT_DOMAINS"; then
            printf "%s\n" "$wildcard" >> dead_wildcards.tmp
        fi
    done < "$WILDCARDS"
    [[ ! -f dead_wildcards.tmp ]] && return

    # Remove unused wildcards from raw file and wildcards file
    comm -23 "$RAW" dead_wildcards.tmp > raw.tmp
    comm -23 "$WILDCARDS" dead_wildcards.tmp > wildcards.tmp
    mv raw.tmp "$RAW"
    mv wildcards.tmp "$WILDCARDS"

    log_event "$(<dead_wildcards.tmp)" dead wildcard
}

check_dead() {
    # Exclude wildcards and root domains of subdomains
    comm -23 "$RAW" <(sort "$ROOT_DOMAINS" "$WILDCARDS") > raw.tmp

    find_dead raw.tmp || return

    # Rename temporary dead file to be added into dead cache later
    mv dead.tmp dead_in_raw.tmp

    # Remove dead domains from raw file
    comm -23 "$RAW" dead_in_raw.tmp > raw.tmp && mv raw.tmp "$RAW"

    log_event "$(<dead_in_raw.tmp)" dead raw
}

check_alive() {
    find_dead "$DEAD_DOMAINS" || return

    # Get resurrected domains in dead domains file
    # (dead domains file is unsorted)
    alive_domains="$(comm -23 <(sort "$DEAD_DOMAINS") <(sort dead.tmp))"
    [[ -z "$alive_domains" ]] && return

    # Update dead domains file to only include dead domains
    cp dead.tmp "$DEAD_DOMAINS"
    format_file "$DEAD_DOMAINS"

    # Strip away subdomains from alive domains as subdomains
    # are not supposed to be in raw file
    while read -r subdomain; do
        alive_domains="$(printf "%s" "$alive_domains" \
            | sed "s/^${subdomain}\.//" | sort -u)"
    done < "$SUBDOMAINS_TO_REMOVE"

    # Add resurrected domains to raw file
    printf "%s\n" "$alive_domains" >> "$RAW"
    format_file "$RAW"

    log_event "$alive_domains" resurrected dead_domains_file
}

# Function 'find_dead' finds dead domains from a given file by first formatting
# the file and then processing it through AdGuard's Dead Domains Linter.
# Input:
#   $1: file to process
# Output:
#   dead.tmp (if dead domains found)
#   exit status 1 (if dead domains not found)
find_dead() {
    sed 's/^/||/; s/$/^/' "$1" > formatted_domains.tmp
    dead-domains-linter -i formatted_domains.tmp --export dead.tmp
    [[ ! -s dead.tmp ]] && return 1 || return 0
}

# Function 'log_event' logs domain processing events into the domain log.
# $1: domains to log stored in a variable.
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
    find . -maxdepth 1 -type f -name '*.tmp' -delete

    # Prune old entries from dead domains file
    if (( $(wc -l < "$DEAD_DOMAINS") > 5000 )); then
        sed -i '1,100d' "$DEAD_DOMAINS"
    fi
}

trap cleanup EXIT

main

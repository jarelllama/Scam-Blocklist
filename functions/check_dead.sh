#!/bin/bash

# Checks for dead/resurrected domains and removes/adds them accordingly.
# Last code review: 8 April 2024

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'
readonly WILDCARDS='data/wildcards.txt'
readonly REDUNDANT_DOMAINS='data/redundant_domains.txt'
readonly DOMAIN_LOG='config/domain_log.csv'
TIME_FORMAT="$(date -u +"%H:%M:%S %d-%m-%y")"

main() {
    # Install AdGuard's Dead Domains Linter
    npm install -g @adguard/dead-domains-linter &> /dev/null

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

    # Cache dead domains to filter out from newly retrieved domains
    # (done last to skip alive domains check)
    cat dead_raw.tmp dead_subdomains.tmp dead_redundant.tmp >> "$DEAD_DOMAINS"
    format_file "$DEAD_DOMAINS"
}

# Function 'check_subdomains' removes dead domains from the subdomains file
# and raw file.
check_subdomains() {
    find_dead "$SUBDOMAINS" || return

    # Remove domains from subdomains file
    comm -23 "$SUBDOMAINS" dead.tmp > subdomains.tmp
    mv subdomains.tmp "$SUBDOMAINS"

    # Copy temporary dead file to be added into dead cache later
    cp dead.tmp dead_subdomains.tmp

    # Strip dead domains to their root domains
    while read -r subdomain; do
        sed -i "s/^${subdomain}\.//" dead.tmp
    done < "$SUBDOMAINS_TO_REMOVE"

    format_file dead.tmp

    # Remove dead root domains from raw file and root domains file
    comm -23 "$RAW" dead.tmp > raw.tmp
    comm -23 "$ROOT_DOMAINS" dead.tmp > root.tmp
    mv raw.tmp "$RAW"
    mv root.tmp "$ROOT_DOMAINS"

    log_event "$(<dead.tmp)" dead raw
}

# Function 'check_redundant' removes dead domains from the redundant domains
# file and raw file.
check_redundant() {
    find_dead "$REDUNDANT_DOMAINS" || return

    # Remove dead domains from redundant domains file
    comm -23 "$REDUNDANT_DOMAINS" dead.tmp > redundant.tmp
    mv redundant.tmp "$REDUNDANT_DOMAINS"

    # Copy temporary dead file to be added into dead cache later
    cp dead.tmp dead_redundant.tmp

    # Find unused wildcards
    while read -r wildcard; do
        # If no matches, consider wildcard as unused/dead
        ! grep -q "\.${wildcard}$" "$REDUNDANT_DOMAINS" \
            && printf "%s\n" "$wildcard" >> dead_wildcards.tmp
    done < "$WILDCARDS"
    [[ ! -f dead_wildcards.tmp ]] && return

    # Remove unused wildcards from raw file and wildcards file
    comm -23 "$RAW" dead_wildcards.tmp > raw.tmp
    comm -23 "$WILDCARDS" dead_wildcards.tmp > wildcards.tmp
    mv raw.tmp "$RAW"
    mv wildcards.tmp "$WILDCARDS"

    log_event "$(<dead_wildcards.tmp)" dead wildcard
}

# Function 'check_dead' removes dead domains from the raw file.
check_dead() {
    # Exclude wildcards and root domains of subdomains
    comm -23 "$RAW" <(sort "$ROOT_DOMAINS" "$WILDCARDS") > raw.tmp

    find_dead raw.tmp || return

    # Copy temporary dead file to be added into dead cache later
    cp dead.tmp dead_raw.tmp

    # Remove dead domains from raw file
    comm -23 "$RAW" dead.tmp > raw.tmp
    mv raw.tmp "$RAW"

    log_event "$(<dead.tmp)" dead raw
}

# Function 'check_alive' finds resurrected domains in the dead domains file
# and adds them back into the raw file.
check_alive() {
    find_dead "$DEAD_DOMAINS"  # No need to return if no dead found

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
        alive_domains="$(echo "$alive_domains" \
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
#   dead.tmp
#   return 1 if dead domains not found
find_dead() {
    temp_file="$(basename "$1").tmp"
    sed 's/.*/||&^/' "$1" > "$temp_file"
    dead-domains-linter -i "$temp_file" --export dead.tmp
    printf "\n"
    [[ ! -s dead.tmp ]] && return 1

    # The Dead Domains Linter exports without an ending new line
    printf "\n" >> dead.tmp
    return
}

# Function 'log_event' logs domain processing events into the domain log.
#   $1: domains to log stored in a variable.
#   $2: event type (dead, whitelisted, etc.)
#   $3: source
log_event() {
    [[ -z "$1" ]] && return  # Return if no domains passed
    local source="${source:-$3}"
    printf "%s\n" "$1" | awk -v event="$2" -v source="$source" -v time="$TIME_FORMAT" \
        '{print time "," event "," $0 "," source}' >> "$DOMAIN_LOG"
}

# Function 'format_file' calls a shell wrapper to standardize the format
# of a file.
#   $1: file to format
format_file() {
    bash functions/tools.sh format "$1"
}

cleanup() {
    find . -maxdepth 1 -type f -name "*.tmp" -delete

    # Prune old entries from dead domains file
    lines="$(wc -l < "$DEAD_DOMAINS")"
    if (( lines > 6000 )); then
        sed -i "1,$(( lines - 6000 ))d" "$DEAD_DOMAINS"
    fi
}

trap cleanup EXIT

main

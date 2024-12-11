#!/bin/bash

# Checks for dead/resurrected domains and removes/adds them accordingly.

readonly FUNCTION='bash scripts/tools.sh'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'

main() {
    # Install AdGuard's Dead Domains Linter
    if ! command -v dead-domains-linter &> /dev/null; then
        npm install -g @adguard/dead-domains-linter > /dev/null
    fi

    # Split raw file into 2 parts for each job
    split -d -l $(( $(wc -l < "$RAW") / 2 )) "$RAW"

    # Part 1 (default)
    if [[ "$1" != 'part2' ]]; then
        check_dead x00
        save_dead
        exit 0
    fi

    # Part 2
    check_dead x01
    save_dead
    check_alive

    # Remove dead domains from subdomains file
    comm -23 "$SUBDOMAINS" "$DEAD_DOMAINS" > temp
    mv temp "$SUBDOMAINS"

    cat "$DEAD_DOMAINS"  # For debugging

    # Strip subdomains from dead domains
    while read -r subdomain; do
        mawk 'sub(^)'
        sed "s/^${subdomain}\.//" "$DEAD_DOMAINS" \
            | sort -o dead_no_subdomains.tmp
    done < "$SUBDOMAINS_TO_REMOVE"

    # Remove dead domains from the various files
    # grep is used here because the dead domains file is unsorted
    for file in "$RAW" "$RAW_LIGHT" "$ROOT_DOMAINS"; do
        comm -23 "$file" dead_no_subdomains.tmp > temp
        mv temp "$file"
    done

    # Call shell wrapper to log number of dead domains in domain log
    #$FUNCTION --log-domains dead.tmp dead raw
    $FUNCTION --log-domains "$(wc -l < "$DEAD_DOMAINS")" "dead_domains" raw
}

# Function 'check_dead' removes dead domains in the given file from the raw
# file, raw light file and subdomains file.
# Input:
#   $1: file to process
check_dead() {
    # Include subdomains found in the given file. Exclude the root domains
    # since the subdomains were what was retrieved during domain retrieval.
    comm -23 <(sort <(grep -Ef "$1" "$SUBDOMAINS") "$1") "$ROOT_DOMAINS" \
        > domains.tmp

    find_dead_in domains.tmp || return

    # Collate dead domains including subdomains
    cp dead.tmp dead_saved.tmp
}

# Function 'check_alive' finds resurrected domains in the dead domains file
# (also called the dead domains cache) and adds them back into the raw file.
#
# Note that resurrected domains are not added back into the raw light file due
# to limitations in the way the dead domains are recorded.
check_alive() {
    find_dead_in "$DEAD_DOMAINS"  # No need to return if no dead domains found

    # Get resurrected domains in dead domains file
    comm -23 <(sort "$DEAD_DOMAINS") dead.tmp > alive.tmp

    [[ ! -s alive.tmp ]] && return

    # Update dead domains file to only include dead domains
    # grep is used here because the dead domains file is unsorted
    grep -xFf dead.tmp "$DEAD_DOMAINS" > temp
    mv temp "$DEAD_DOMAINS"

    # Add resurrected domains to raw file
    # Note that resurrected subdomains are added back too and will be processed
    # by the validation check outside of this script.
    sort -u alive.tmp "$RAW" -o "$RAW"

    # Call shell wrapper to log number of resurrected domains in domain log
    #$FUNCTION --log-domains alive.tmp resurrected dead_domains_file
    $FUNCTION --log-domains "$(wc -l < alive.tmp)" resurrected_count dead_domains_file
}

# Function 'find_dead_in' finds dead domains in a given file by formatting the
# file and then processing it through AdGuard's Dead Domains Linter.
# Input:
#   $1: file to process
# Output:
#   dead.tmp
#   return 1 (if dead domains not found)
find_dead_in() {
    local temp
    temp="$(basename "$1").tmp"
    local execution_time
    execution_time="$(date +%s)"

    # Format to Adblock Plus syntax for Dead Domains Linter
    sed 's/.*/||&^/' "$1" > "$temp"

    printf "\n"
    dead-domains-linter -i "$temp" --export dead.tmp

    sort -u dead.tmp -o dead.tmp

    printf "Processing time: %s second(s)\n" "$(( $(date +%s) - execution_time ))"

    # Return 1 if no dead domains were found
    [[ ! -s dead.tmp ]] && return 1 || return 0
}

# Function 'save_dead' collates the dead domains into one file that can later
# be used to remove dead domains from other files.
save_dead() {
    [[ -f dead_saved.tmp ]] || return

    # Cache dead domains to be used as a filter for newly retrieved domains
    # (done last to skip alive check)
    # Note the dead domains file should remain unsorted
    cat dead_saved.tmp >> "$DEAD_DOMAINS"
}

cleanup() {
    find . -maxdepth 1 -type f -name "*.tmp" -delete
    find . -maxdepth 1 -type f -name "x??" -delete

    # Call shell wrapper to prune old entries from dead domains file
    $FUNCTION --prune-lines "$DEAD_DOMAINS" 50000
}

# Entry point

trap cleanup EXIT

$FUNCTION --format-all

main "$1"
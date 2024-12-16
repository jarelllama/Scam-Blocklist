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

    case "$1" in
        'checkalive')
            # The alive check should be done before the new dead domains are
            # added to the dead domains file as to not process these domains
            # twice.
            check_alive
            ;;
        'part1')
            # Sometimes an x02 exists
            [[ -f x02 ]] && cat x02 >> x01
            check_dead x01
            ;;
        'part2')
            # Sometimes an x02 exists
            [[ -f x02 ]] && cat x02 >> x01
            check_dead x01
            ;;
        'remove')
            remove_dead
            ;;
        *)
            printf "\n\e[1;31mNo argument passed.\e[0m\n\n"
            exit 1
            ;;
    esac
}

# Function 'check_dead' finds dead domains and collates them into the dead
# domains file to be removed from the various files later.
check_dead() {
    # Include subdomains found in the given file. Exclude the root domains
    # since the subdomains were what was retrieved during domain retrieval.
    comm -23 <(sort <(grep -Ef "$1" "$SUBDOMAINS") "$1") "$ROOT_DOMAINS" \
        > domains.tmp

    find_dead_in domains.tmp || return

    cp dead.tmp dead_domains.tmp

    if [[ -f dead_domains.tmp ]]; then
        # Cache dead domains to be removed from the various files later
        # and to act as a filter for newly retrieved domains.
        # Note the dead domains file should remain unsorted.
        cat dead_domains.tmp >> "$DEAD_DOMAINS"
    fi
}

# Function 'check_alive' finds resurrected domains in the dead domains file
# (also called the dead domains cache) and adds them back into the raw file.
#
# Note that resurrected domains are not added back into the raw light file due
# to limitations in the way the dead domains are recorded.
check_alive() {
    find_dead_in "$DEAD_DOMAINS"  # No need to return if no dead domains found

    # Get resurrected domains in dead domains file
    comm -23 <(sort "$DEAD_DOMAINS") dead.tmp > alive_domains.tmp

    [[ ! -s alive_domains.tmp ]] && return

    # Update dead domains file to only include dead domains
    # grep is used here because the dead domains file is unsorted
    grep -xFf dead.tmp "$DEAD_DOMAINS" > temp
    mv temp "$DEAD_DOMAINS"

    # Add resurrected domains to raw file
    # Note that resurrected subdomains are added back too and will be processed
    # by the validation check outside of this script.
    sort -u alive_domains.tmp "$RAW" -o "$RAW"

    # Call shell wrapper to log number of resurrected domains in domain log
    #$FUNCTION --log-domains alive_domains.tmp resurrected dead_domains_file
    $FUNCTION --log-domains "$(wc -l < alive_domains.tmp)" resurrected_count dead_domains_file
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

# Function 'remove_dead' removes dead domains from the raw file, raw light
# file, root domains file and subdomains file.
remove_dead() {
    sort "$DEAD_DOMAINS" -o dead.tmp

    # Remove dead domains from subdomains file
    comm -23 "$SUBDOMAINS" dead.tmp > temp
    mv temp "$SUBDOMAINS"

    # Strip subdomains from dead domains
    while read -r subdomain; do
        sed -i "s/^${subdomain}\.//" dead.tmp
    done < "$SUBDOMAINS_TO_REMOVE"
    sort -u dead.tmp -o dead.tmp

    raw_count="$(wc -l < "$RAW")"

    # Remove dead domains from the various files
    for file in "$RAW" "$RAW_LIGHT" "$ROOT_DOMAINS"; do
        comm -23 "$file" dead.tmp > temp
        mv temp "$file"
    done

    dead_count="$(( raw_count - $(wc -l < "$RAW") ))"

    # Call shell wrapper to log number of dead domains in domain log
    #$FUNCTION --log-domains dead.tmp dead raw
    $FUNCTION --log-domains "$dead_count" dead_count raw
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
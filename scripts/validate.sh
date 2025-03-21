#!/bin/bash

# Validate and tidy the files in the repo including filtering the raw file.

readonly FUNCTION='bash scripts/tools.sh'
readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly BLACKLIST='config/blacklist.txt'
readonly REVIEW_CONFIG='config/review_config.csv'
readonly SUBDOMAINS='config/subdomains.txt'
readonly DOMAIN_REGEX='(?:([\p{L}\p{N}][\p{L}\p{N}-]*[\p{L}\p{N}]|[\p{L}\p{N}])\.)+[\p{L}}][\p{L}\p{N}-]*[\p{L}\p{N}]'
readonly ALIVE_DOMAINS_URL='https://raw.githubusercontent.com/jarelllama/Dead-Domains/refs/heads/main/alive_domains.txt'
readonly DEAD_DOMAINS_URL='https://raw.githubusercontent.com/jarelllama/Dead-Domains/refs/heads/main/dead_domains.txt'
readonly PARKED_DOMAINS_URL='https://raw.githubusercontent.com/jarelllama/Parked-Domains/refs/heads/main/parked_domains.txt'
readonly UNPARKED_DOMAINS_URL='https://raw.githubusercontent.com/jarelllama/Parked-Domains/refs/heads/main/unparked_domains.txt'

main() {
    printf "\n\e[1mProcessing dead domains\e[0m\n"
    process_resurrected_domains
    process_dead_domains

    printf "\n\e[1mProcessing parked domains\e[0m\n"
    process_unparked_domains
    process_parked_domains

    # Update subdomains file before downloading the toplist
    update_subdomains_file

    $FUNCTION --download-toplist

    # Tidy blacklist before getting new blacklisted entries from the review
    # config file
    tidy_blacklist

    $FUNCTION --update-review-config

    # Store whitelist and blacklist as regex expressions
    whitelist="$($FUNCTION --get-whitelist)"
    blacklist="$($FUNCTION --get-blacklist)"
    readonly whitelist blacklist

    validate_raw_file

    prune_files
}

# Add resurrected domains to the raw file and remove them from the dead domains
# file.
process_resurrected_domains() {
    local count_before count_after resurrected_count

    # alive_domains.tmp can be manually created for testing
    if [[ ! -f alive_domains.tmp ]]; then
        # Get resurrected domains from jarelllama/Dead-Domains
        curl -sSL --retry 2 --retry-all-errors "$ALIVE_DOMAINS_URL" \
            -o alive_domains.tmp \
            || error 'Error downloading alive domains file.'
    fi

    count_before="$(wc -l < "$RAW")"

    # Add resurrected domains found in the dead domains file to the raw file
    comm -12 alive_domains.tmp <(sort "$DEAD_DOMAINS") \
        | sort -u - "$RAW" -o "$RAW"

    # Remove resurrected domains from the dead domains file
    # grep is used here as the dead domains file should remain unsorted
    # Using grep is faster than a loop in mawk here
    grep -vxFf alive_domains.tmp "$DEAD_DOMAINS" > temp || true
    mv temp "$DEAD_DOMAINS"

    count_after="$(wc -l < "$RAW")"

    resurrected_count="$(( count_after - count_before ))"

    printf "Added %s resurrected domains to the raw file.\n" \
        "$resurrected_count"

    $FUNCTION --log-domains "$resurrected_count" resurrected_count \
        dead_domains_file
}

# Remove dead domains from the raw file.
process_dead_domains() {
    local count_before count_after dead_count

    # dead_domains.tmp can be manually created for testing
    if [[ ! -f dead_domains.tmp ]]; then
        # Get dead domains from jarelllama/Dead-Domains
        curl -sSL --retry 2 --retry-all-errors "$DEAD_DOMAINS_URL" \
            -o dead_domains.tmp \
            || error 'Error downloading dead domains file.'
    fi

    # Collate dead domains that are found in the raw file to the dead domains
    # file
    comm -12 dead_domains.tmp "$RAW" >> "$DEAD_DOMAINS"

    count_before="$(wc -l < "$RAW")"

    # Remove dead domains from the raw file
    comm -23 "$RAW" <(sort "$DEAD_DOMAINS") > temp
    mv temp "$RAW"

    # Remove dead domains from the raw light file
    comm -23 "$RAW_LIGHT" <(sort "$DEAD_DOMAINS") > temp
    mv temp "$RAW_LIGHT"

    count_after="$(wc -l < "$RAW")"

    dead_count="$(( count_before - count_after ))"

    printf "Removed %s dead domains from the raw file.\n" "$dead_count"

    $FUNCTION --log-domains "$dead_count" dead_count raw
}

# Add unparked domains to the raw file and remove them from the parked domains
# file.
process_unparked_domains() {
    local count_before count_after unparked_count

    # unparked_domains.tmp can be manually created for testing
    if [[ ! -f unparked_domains.tmp ]]; then
        # Get unparked domains from jarelllama/Parked-Domains
        curl -sSL --retry 2 --retry-all-errors "$UNPARKED_DOMAINS_URL" \
            -o unparked_domains.tmp \
            || error 'Error downloading unparked domains file.'
    fi

    count_before="$(wc -l < "$RAW")"

    # Add unparked domains found in the parked domains file to the raw file
    comm -12 unparked_domains.tmp <(sort "$PARKED_DOMAINS") \
        | sort -u - "$RAW" -o "$RAW"

    # Remove unparked domains from the parked domains file
    # grep is used here as the parked domains file should remain unsorted
    # Using grep is faster than a loop in mawk here
    grep -vxFf unparked_domains.tmp "$PARKED_DOMAINS" > temp || true
    mv temp "$PARKED_DOMAINS"

    count_after="$(wc -l < "$RAW")"

    unparked_count="$(( count_after - count_before ))"

    printf "Added %s unparked domains to the raw file.\n" \
        "$unparked_count"

    $FUNCTION --log-domains "$unparked_count" unparked_count \
        parked_domains_file
}

# Remove parked domains from the raw file.
process_parked_domains() {
    local count_before count_after parked_count

    # parked_domains.tmp can be manually created for testing
    if [[ ! -f parked_domains.tmp ]]; then
        # Get parked domains from jarelllama/Parked-Domains
        curl -sSL --retry 2 --retry-all-errors "$PARKED_DOMAINS_URL" \
            -o parked_domains.tmp \
            || error 'Error downloading parked domains file.'
    fi

    # Collate parked domains that are found in the raw file to the parked
    # domains file
    comm -12 parked_domains.tmp "$RAW" >> "$PARKED_DOMAINS"

    count_before="$(wc -l < "$RAW")"

    # Remove parked domains from the raw file
    comm -23 "$RAW" <(sort "$PARKED_DOMAINS") > temp
    mv temp "$RAW"

    # Remove parked domains from the raw light file
    comm -23 "$RAW_LIGHT" <(sort "$PARKED_DOMAINS") > temp
    mv temp "$RAW_LIGHT"

    count_after="$(wc -l < "$RAW")"

    parked_count="$(( count_before - count_after ))"

    printf "Removed %s parked domains from the raw file.\n" "$parked_count"

    $FUNCTION --log-domains "$parked_count" parked_count raw
}

# Update the subdomains file.
update_subdomains_file() {
    {
        # Get subdomains less than or equal to 3 characters and occur more
        # than or equal to 10 times
        mawk -F '.' '{ print $1 }' "$RAW" | sort | uniq -c | sort -nr \
            | mawk '$1 >= 10 && length($2) <= 3 { print $2 }'

        # Get manually added subdomains
        mawk 'length($0) > 3 { print }' "$SUBDOMAINS"
    } | sort -u -o "$SUBDOMAINS"
}

# Tidy the blacklist.
tidy_blacklist() {
    {
        # Remove entries that are not found in the raw file and toplist
        comm -12 "$RAW" toplist.tmp \
            | mawk -v blacklist="$($FUNCTION --get-blacklist)" '
            $0 ~ blacklist' | grep -of "$BLACKLIST"

        # Keep entries with whitelisted TLDs
        awk '/\.(gov|edu|mil)(\.[a-z]{2})?$/' "$BLACKLIST"
    } | sort -u -o "$BLACKLIST"
}

# Used by validate_raw_file() to remove entries from the raw file and log them
# into the domain log.
# Input:
#   $1: entries to process passed in a variable
#   $2: tag to be shown in the domain log
#   --preserve: keep entries in the raw file
# Output:
#   filter_log.tmp (if filtered domains found)
filter() {
    local entries="$1"
    local tag="$2"

    # Return if no entries were passed
    [[ -z "$entries" ]] && return

    if [[ "$3" == '--preserve' ]]; then
        # Save entries into the review config file
        mawk -v reason="$tag" '{ print "raw," $0 "," reason ",," }' \
            <<< "$entries" >> "$REVIEW_CONFIG"

        # Remove duplicates from the review config file
        mawk '!seen[$0]++' "$REVIEW_CONFIG" > temp
        mv temp "$REVIEW_CONFIG"
    else
        # Remove entries from the raw file
        comm -23 "$RAW" <(printf "%s" "$entries") > temp
        mv temp "$RAW"
    fi

    # Print filtered entries
    mawk -v tag="$tag" '{ print $0 " (" tag ")" }' <<< "$entries"

    $FUNCTION --log-domains "$entries" "$tag" raw
}

# Validate the entries in the raw file.
validate_raw_file() {
    printf "\n\e[1mValidating raw file\e[0m\nLog:\n"

    # Remove non-domain entries
    filter "$(grep -vP "^${DOMAIN_REGEX}$" "$RAW")" invalid

    # Remove non-domain entries from the raw light file early to ensure proper
    # Punycode conversion
    comm -23 "$RAW_LIGHT" <(grep -vP "^${DOMAIN_REGEX}$" "$RAW_LIGHT") > temp
    mv temp "$RAW_LIGHT"

    # Convert Unicode to Punycode
    $FUNCTION --convert-unicode "$RAW"
    $FUNCTION --convert-unicode "$RAW_LIGHT"

    # Remove whitelisted domains excluding blacklisted domains
    filter "$(awk -v whitelist="$whitelist" -v blacklist="$blacklist" '
        $0 ~ whitelist && $0 !~ blacklist' "$RAW")" whitelist

    # Get domains with whitelisted TLDs excluding blacklisted domains
    filter "$(awk -v blacklist="$blacklist" '
        /\.(gov|edu|mil)(\.[a-z]{2})?$/ && $0 !~ blacklist' "$RAW"
        )" whitelisted_tld --preserve

    # Get domains in the toplist excluding blacklisted domains
    filter "$(comm -12 "$RAW" toplist.tmp \
        | mawk -v blacklist="$blacklist" '$0 !~ blacklist')" toplist --preserve

    # Save changes to the raw light file
    comm -12 "$RAW_LIGHT" "$RAW" > temp
    mv temp "$RAW_LIGHT"
}

# Prune files to keep them within a certain size.
prune_files() {
    # Prune logs
    $FUNCTION --prune-lines config/source_log.csv 10000
    # 500,000 is enough for a month's worth of logs
    $FUNCTION --prune-lines config/domain_log.csv 500000

    # Prune dead domains file
    $FUNCTION --prune-lines data/dead_domains.txt 100000

    # Prune parked domains file
    $FUNCTION --prune-lines data/parked_domains.txt 100000
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

trap 'rm ./*.tmp 2> /dev/null || true' EXIT

$FUNCTION --format-files

main "$1"

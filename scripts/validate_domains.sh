#!/bin/bash

# Process domains in the raw file to ensure it is kept clean and filtered and
# flag entries that require attention.

readonly FUNCTION='bash scripts/tools.sh'
readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly REVIEW_CONFIG='config/review_config.csv'
readonly DOMAIN_REGEX='(?:([\p{L}\p{N}][\p{L}\p{N}-]*[\p{L}\p{N}]|[\p{L}\p{N}])\.)+[\p{L}}][\p{L}\p{N}-]*[\p{L}\p{N}]'
readonly ALIVE_DOMAINS_URL='https://raw.githubusercontent.com/jarelllama/Dead-Domains/refs/heads/main/scripts/alive_domains.txt'
readonly DEAD_DOMAINS_URL='https://raw.githubusercontent.com/jarelllama/Dead-Domains/refs/heads/main/scripts/dead_domains.txt'
readonly PARKED_DOMAINS_URL='https://raw.githubusercontent.com/jarelllama/Parked-Domains/refs/heads/main/scripts/parked_domains.txt'
readonly UNPARKED_DOMAINS_URL='https://raw.githubusercontent.com/jarelllama/Parked-Domains/refs/heads/main/scripts/unparked_domains.txt'

main() {
    $FUNCTION --download-toplist

    $FUNCTION --update-review-config

    printf "\n\e[1mProcessing dead domains\e[0m\n"

    process_resurrected_domains

    process_dead_domains

    printf "\n\e[1mProcessing parked domains\e[0m\n"

    process_unparked_domains

    process_parked_domains

    validate_raw_file
}

# Remove entries from the raw file and log the entries into the domain log.
# Input:
#   $1: entries to process passed in a variable
#   $2: tag to be shown in the domain log
#     --preserve:  keep entries in the raw file
# Output:
#   filter_log.tmp (if filtered domains found)
filter() {
    local entries="$1"
    local tag="$2"

    # Return if no entries passed
    [[ -z "$entries" ]] && return

    if [[ "$3" == '--preserve' ]]; then
        # Save entries into the review config file
        mawk -v reason="$tag" '{ print "raw," $0 "," reason ",," }' \
            <<< "$entries" >> "$REVIEW_CONFIG"

        # Remove duplicates
        mawk '!seen[$0]++' "$REVIEW_CONFIG" > temp
        mv temp "$REVIEW_CONFIG"
    else
        # Remove entries from the raw file
        comm -23 "$RAW" <(printf "%s" "$entries") > temp
        mv temp "$RAW"
    fi

    # Record entries into the filter log for console output
    mawk -v tag="$tag" '{ print $0 " (" tag ")" }' \
        <<< "$entries" >> filter_log.tmp

    $FUNCTION --log-domains "$entries" "$tag" raw
}

process_resurrected_domains() {
    local count_before count_after resurrected_count
    local size=100000

    # alive_domains.tmp can be manually created for testing
    if [[ ! -f alive_domains.tmp ]]; then
        # Get resurrected domains from jarelllama/Dead-Domains
        curl -sSL --retry 2 --retry-all-errors "$ALIVE_DOMAINS_URL" \
            -o alive_domains.tmp \
            || error 'Error downloading alive domains file.'
    fi

    count_before="$(wc -l < "$RAW")"

    # Add resurrected domains found in the dead domains file to the raw file
    comm -12 alive_domains.tmp "$DEAD_DOMAINS" | sort -u - "$RAW" -o "$RAW"

    # Remove resurrected domains from the dead domains file
    comm -23 "$DEAD_DOMAINS" alive_domains.tmp > temp
    mv temp "$DEAD_DOMAINS"

    count_after="$(wc -l < "$RAW")"

    resurrected_count="$(( count_after - count_before ))"

    printf "Added %s resurrected domains to the raw file.\n" \
        "$resurrected_count"

    $FUNCTION --log-domains "$resurrected_count" resurrected_count \
        dead_domains_file

    # Prune the dead domains file to keep it within a certain size
    $FUNCTION --prune-lines "$DEAD_DOMAINS" "$size"
}

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

process_unparked_domains() {
    local count_before count_after unparked_count
    local size=100000

    # unparked_domains.tmp can be manually created for testing
    if [[ ! -f unparked_domains.tmp ]]; then
        # Get unparked domains from jarelllama/Parked-Domains
        curl -sSL --retry 2 --retry-all-errors "$UNPARKED_DOMAINS_URL" \
            -o unparked_domains.tmp \
            || error 'Error downloading unparked domains file.'
    fi

    count_before="$(wc -l < "$RAW")"

    # Add unparked domains found in the parked domains file to the raw file
    comm -12 unparked_domains.tmp "$PARKED_DOMAINS" \
        | sort -u - "$RAW" -o "$RAW"

    # Remove unparked domains from the parked domains file
    comm -23 "$PARKED_DOMAINS" unparked_domains.tmp > temp
    mv temp "$PARKED_DOMAINS"

    count_after="$(wc -l < "$RAW")"

    unparked_count="$(( count_after - count_before ))"

    printf "Added %s unparked domains to the raw file.\n" \
        "$unparked_count"

    $FUNCTION --log-domains "$unparked_count" unparked_count \
        parked_domains_file

    # Prune the parked domains file to keep it within a certain size
    $FUNCTION --prune-lines "$PARKED_DOMAINS" "$size"
}

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

validate_raw_file() {
    # Remove non-domain entries
    filter "$(grep -vP "^${DOMAIN_REGEX}$" "$RAW")" invalid

    # Remove non-domain entries from the raw light file early to ensure proper
    # Punycode conversion
    comm -23 "$RAW_LIGHT" <(grep -vP "^${DOMAIN_REGEX}$" "$RAW_LIGHT") > temp
    mv temp "$RAW_LIGHT"

    # Convert Unicode to Punycode in the raw file and the raw light file
    $FUNCTION --convert-unicode "$RAW"
    $FUNCTION --convert-unicode "$RAW_LIGHT"

    # Store whitelist and blacklist as a regex expression
    whitelist="$($FUNCTION --get-whitelist)"
    blacklist="$($FUNCTION --get-blacklist)"
    readonly whitelist blacklist

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

    # Return if no filtering done
    [[ ! -s filter_log.tmp ]] && return

    # Print filter log
    printf "\n\e[1mProblematic domains (%s):\e[0m\n" \
        "$(wc -l < filter_log.tmp)"
    sed 's/(toplist)/& - \o033[31mmanual verification required\o033[0m/' \
        filter_log.tmp

    $FUNCTION --send-telegram \
        "Validation: problematic domains found\n\n$(<filter_log.tmp)"

    printf "\nTelegram notification sent.\n"
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

trap 'rm ./*.tmp temp 2> /dev/null || true' EXIT

$FUNCTION --format-files

main "$1"

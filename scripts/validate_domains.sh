#!/bin/bash

# Validate domains in the raw file via a variety of checks and flag entries
# that require attention.

readonly FUNCTION='bash scripts/tools.sh'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly REVIEW_CONFIG='config/review_config.csv'
readonly DOMAIN_REGEX='[[:alnum:]][[:alnum:].-]*[[:alnum:]]\.[[:alnum:]-]*[a-z]{2,}[[:alnum:]-]*'

main() {
    $FUNCTION --download-toplist

    $FUNCTION --update-review-config

    validate
}

# Remove entries from the raw file and log the entries into the domain log.
# Input:
#   $1: entries to process passed in a variable
#   $2: tag to be shown in the domain log
#   --preserve: keep entries in the raw file
# Output:
#   filter_log.tmp (if filtered domains found)
filter() {
    local entries="$1"
    local tag="$2"

    # Return if no entries passed
    [[ -z "$entries" ]] && return

    if [[ "$3" == '--preserve' ]]; then
        # Save entries into review config file
        mawk -v reason="$tag" '{ print "raw," $0 "," reason ",," }' \
            <<< "$entries" >> "$REVIEW_CONFIG"

        # Remove duplicates
        mawk '!seen[$0]++' "$REVIEW_CONFIG" > temp
        mv temp "$REVIEW_CONFIG"
    else
        # Remove entries from raw file
        comm -23 "$RAW" <(printf "%s" "$entries") > temp
        mv temp "$RAW"
    fi

    # Record entries into filter log for console output
    mawk -v tag="$tag" '{ print $0 " (" tag ")" }' \
        <<< "$entries" >> filter_log.tmp

    $FUNCTION --log-domains "$entries" "$tag" raw
}

# Validate raw file.
validate() {
    # Convert Unicode to Punycode in raw file and raw light file
    $FUNCTION --convert-unicode "$RAW"
    $FUNCTION --convert-unicode "$RAW_LIGHT"

    # Remove non-domain entries including IP addresses excluding Punycode
    filter "$(awk "!/^${DOMAIN_REGEX}$/" "$RAW")" invalid

    # Store whitelist and blacklist as a regex expression
    whitelist="$($FUNCTION --get-whitelist)"
    blacklist="$($FUNCTION --get-blacklist)"
    readonly whitelist blacklist

    # Remove whitelisted domains excluding blacklisted domains
    filter "$(awk -v whitelist="$whitelist" -v blacklist="$blacklist" '
        $0 ~ whitelist && $0 !~ blacklist' "$RAW")" whitelist

    # Remove domains with whitelisted TLDs excluding blacklisted domains
    filter "$(awk -v blacklist="$blacklist" '
        /\.(gov|edu|mil)(\.[a-z]{2})?$/ && $0 !~ blacklist
        ' "$RAW")" whitelisted_tld

    # Find domains in toplist excluding blacklisted domains
    filter "$(mawk -v blacklist="$blacklist" '
        NR==FNR { lines[$0]; next } $0 in lines && $0 !~ blacklist
        ' "$RAW" toplist.tmp)" toplist --preserve

    # Return if no filtering done
    [[ ! -f filter_log.tmp ]] && return

    # Save changes to raw light file
    comm -12 "$RAW_LIGHT" "$RAW" > temp
    mv temp "$RAW_LIGHT"

    # Print filter log
    printf "\n\e[1mProblematic domains (%s):\e[0m\n" \
        "$(wc -l < filter_log.tmp)"
    sed 's/(toplist)/& - \o033[31mmanual verification required\o033[0m/' \
        filter_log.tmp

    [[ ! -s filter_log.tmp ]] && return

    $FUNCTION --send-telegram \
        "Validation: problematic domains found\n\n$(<filter_log.tmp)"

    printf "\nTelegram notification sent.\n"
}

# Entry point

set -e

trap 'rm ./*.tmp temp 2> /dev/null || true' EXIT

$FUNCTION --format-files

main

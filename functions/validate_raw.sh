#!/bin/bash

# Validates the entries in the raw file via a variety of checks and flags
# entries that require attention.
# Latest code review: 9 April 2024

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly WHITELIST='config/whitelist.txt'
readonly BLACKLIST='config/blacklist.txt'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'

validate_raw() {
    before_count="$(wc -l < "$RAW")"

    # Remove common subdomains
    subdomains_count=0
    while read -r subdomain; do  # Loop through common subdomains
        subdomains="$(grep "^${subdomain}\." "$RAW")" || continue
        subdomains_count="$(( subdomains_count \
            + "$(filter "$subdomains" subdomain --preserve)" ))"

        # Strip subdomains from raw file and raw light file
        sed -i "s/^${subdomain}\.//" "$RAW"
        sed -i "s/^${subdomain}\.//" "$RAW_LIGHT"

        # Save subdomains to be filtered later
        printf "%s\n" "$subdomains" >> subdomains.tmp

        # Save root domains to be filtered later
        printf "%s\n" "$subdomains" | sed "s/^${subdomain}\.//" >> root_domains.tmp

    done < "$SUBDOMAINS_TO_REMOVE"
    sort -u "$RAW" -o "$RAW"
    sort -u "$RAW_LIGHT" -o "$RAW_LIGHT"

    # Remove whitelisted domains, excluding blacklisted domains
    # Note whitelist matching uses keywords
    whitelisted="$(grep -Ff "$WHITELIST" "$RAW" | grep -vxFf "$BLACKLIST")"
    whitelisted_count="$(filter "$whitelisted" whitelisted)"

    # Remove domains that have whitelisted TLDs
    whitelisted_tld="$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' "$RAW")"
    whitelisted_tld_count="$(filter "$whitelisted_tld" whitelisted_tld)"

    # Remove non-domain entries including IP addresses
    # Punycode TLDs (.xn--*) are allowed
    invalid="$(grep -vE '^[[:alnum:].-]+\.[[:alnum:]-]*[a-z][[:alnum:]-]{1,}$' "$RAW")"
    invalid_count="$(filter "$invalid" invalid)"

    # Find matching domains in toplist, excluding blacklisted domains
    # Note the toplist does not include subdomains
    download_toplist
    in_toplist="$(comm -12 toplist.tmp "$RAW" | grep -vxFf "$BLACKLIST")"
    toplist_count="$(filter "$in_toplist" toplist --preserve)"

    # Exit if no filtering done
    [[ ! -f filter_log.tmp ]] && exit

    # Collate only filtered subdomains and root domains into the subdomains
    # file and root domains file
    if [[ -f root_domains.tmp ]]; then
        # Find root domains (subdomains stripped off) in the filtered raw file
        root_domains="$(comm -12 <(sort root_domains.tmp) "$RAW")"

        # Collate filtered root domains to exclude from dead check
        printf "%s\n" "$root_domains" >> "$ROOT_DOMAINS"
        sort -u "$ROOT_DOMAINS" -u "$ROOT_DOMAINS"

        # Collate filtered subdomains for dead check
        grep "\.${root_domains}$" subdomains.tmp >> "$SUBDOMAINS"
        sort -u "$SUBDOMAINS" -u "$SUBDOMAINS"
    fi

    # Print filter log
    printf "\n\e[1mProblematic domains (%s):\e[0m\n" "$(wc -l < filter_log.tmp)"
    sed 's/(toplist)/& - \o033[31mmanual verification required\o033[0m/' filter_log.tmp

    # Send telegram notification
    send_telegram "Problematic domains detected during validation check:\n$(<filter_log.tmp)"

    # Save changes to raw light file
    comm -12 "$RAW" "$RAW_LIGHT" > light.tmp
    mv light.tmp "$RAW_LIGHT"

    total_whitelisted_count="$(( whitelisted_count + whitelisted_tld_count ))"
    after_count="$(wc -l < "$RAW")"

    printf "\nBefore: %s  After: %s  Subdomains: %s  Whitelisted: %s  Invalid %s  Toplist: %s\n\n" \
        "$before_count" "$after_count" "$subdomains_count" "$total_whitelisted_count" \
        "$invalid_count" "$toplist_count"
}

# Function 'filter' logs the given entries and removes them from the raw file.
# Input:
#   $1: entries to process
#   $2: tag given to entries
#   --preserve: set flag to keep entries in the raw file
# Output:
#   Number of entries that were passed
filter() {
    local entries="$1"
    local tag="$2"

    # Return if no entries passed
    [[ -s "$entries" ]] && return

    # Record entries in the filter log
    awk -v tag="$tag" '{print $0 " (" tag ")"}' <<< "$entries" >> filter_log.tmp

    log_event "$entries" "$tag"

    if [[ "$3" != '--preserve' ]]; then
        # Remove entries
        comm -23 "$RAW" <(printf "%s" "$entries") > raw.tmp
        mv raw.tmp "$RAW"
    fi

    # Return the number of entries
    wc -l <<< "$entries"
}

# Function 'send_telegram' sends a Telegram notification with the given
# message.
#   $DISABLE_TELEGRAM: set to true to not send telegram notifications
#   $1: message body
send_telegram() {
    [[ "$DISABLE_TELEGRAM" == true ]] && return

    curl -sX POST \
        -H 'Content-Type: application/json' \
        -d "{\"chat_id\": \"${TELEGRAM_CHAT_ID}\", \"text\": \"$1\"}" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -o /dev/null
}

# Function 'download_toplist' downloads and formats the toplist.
# Output:
#   toplist.tmp
download_toplist() {
    [[ -f toplist.tmp ]] && return

    wget -qO - 'https://tranco-list.eu/top-1m.csv.zip' | gunzip - \
        > toplist.tmp || send_telegram "Error downloading toplist."

    awk -F ',' '{print $2}' toplist.tmp > temp
    mv temp toplist.tmp
    format_file toplist.tmp
}

# Function 'log_event' calls a shell wrapper to log domain processing events
# into the domain log.
#   $1: domains to log stored in a variable
#   $2: event type (dead, whitelisted, etc.)
#   $3: source
log_event() {
    bash functions/tools.sh log_event "$1" "$2" "$3"
}

# Function 'format_file' calls a shell wrapper to standardize the format
# of a file.
#   $1: file to format
format_file() {
    bash functions/tools.sh format "$1"
}

# Entry point

trap 'find . -maxdepth 1 -type f -name "*.tmp" -delete' EXIT

# Format files
for file in config/* data/*; do
    format_file "$file"
done

validate_raw

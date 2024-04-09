#!/bin/bash

# Validates the entries in the raw file via a variety of checks and flags
# entries that require attention.
# Latest code review:

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly WHITELIST='config/whitelist.txt'
readonly BLACKLIST='config/blacklist.txt'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'

validate_raw() {
    # Store domains in the raw file in a variable
    domains="$(<"$RAW")"

    before_count="$(wc -l < "$RAW")"

    # Remove common subdomains
    subdomains_count=0
    while read -r subdomain; do  # Loop through common subdomains
        # Find domains with subdomains and skip to next subdomain if none found
        subdomains="$(grep "^${subdomain}\." <<< "$domains")" || continue

        # Count subdomains
        subdomains_count="$(( subdomains_count \
            + "$(filter "$subdomains" subdomain --preserve)" ))"

        # Strip subdomains down to their root domains
        domains="$(printf "%s" "$domains" | sed "s/^${subdomain}\.//" | sort -u)"

        # Strip subdomains from raw light file
        sed -i "s/^${subdomain}\.//" "$RAW_LIGHT"

        # Collate subdomains for dead check
        printf "%s\n" "$subdomains" >> subdomains.tmp

        # Collate root domains to exclude from dead check
        printf "%s\n" "$subdomains" | sed "s/^${subdomain}\.//" \
            >> root_domains.tmp
    done < "$SUBDOMAINS_TO_REMOVE"
    sort -u "$RAW_LIGHT" -o "$RAW_LIGHT"
    sort -u subdomains.tmp -o subdomains.tmp
    sort -u root_domains.tmp -o root_domains.tmp

    # Remove whitelisted domains, excluding blacklisted domains
    whitelisted="$(grep -Ff "$WHITELIST" <<< "$domains" \
        | grep -vxFf "$BLACKLIST")"
    whitelisted_count="$(filter "$whitelisted" whitelisted)"

    # Remove domains that have whitelisted TLDs
    whitelisted_tld="$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' <<< "$domains")"
    whitelisted_tld_count="$(filter "$whitelisted_tld" whitelisted_tld)"

    # Remove invalid entries and IP addresses. Punycode TLDs (.xn--*) are allowed
    invalid="$(grep -vE '^[[:alnum:].-]+\.[[:alnum:]-]*[a-z][[:alnum:]-]{1,}$' \
        <<< "$domains")"
    invalid_count="$(filter "$invalid" invalid)"

    # Find matching domains in toplist, excluding blacklisted domains
    download_toplist
    domains_in_toplist="$(comm -12 <(printf "%s" "$domains") toplist.tmp \
        | grep -vxFf "$BLACKLIST")"
    toplist_count="$(filter "$domains_in_toplist" toplist --preserve)"

    # Exit if no filtering done
    [[ ! -f filter_log.tmp ]] && exit

    # Collate filtered subdomains and root domains
    if [[ -f root_domains.tmp ]]; then
        # Find root domains (subdomains stripped off) in the filtered domains
        root_domains="$(grep -xF "$domains" root_domains.tmp)"

        # Collate filtered root domains to exclude from dead check
        printf "%s\n" "$root_domains" >> "$ROOT_DOMAINS"

        # Collate filtered subdomains for dead check
        grep "\.${root_domains}$" subdomains.tmp >> "$SUBDOMAINS"

        format_file "$ROOT_DOMAINS"
        format_file "$SUBDOMAINS"
    fi

    # Print filter log
    printf "\n\e[1mProblematic domains (%s):\e[0m\n" "$(wc -l < filter_log.tmp)"
    sed 's/(toplist)/& - \o033[31mmanual verification required\o033[0m/' filter_log.tmp

    # Send telegram notification
    send_telegram "Problematic domains detected during validation check:\n$(<filter_log.tmp)"

    # Save changes to raw file
    printf "%s\n" "$domains" > "$RAW"
    sort -u "$RAW" -o "$RAW"

    # Save changes to raw light file
    comm -12 "$RAW" "$RAW_LIGHT" > light.tmp
    mv light.tmp "$RAW_LIGHT"

    total_whitelisted_count="$(( whitelisted_count + whitelisted_tld_count ))"
    after_count="$(wc -l < "$RAW")"

    printf "\nBefore: %s  After: %s  Subdomains: %s  Whitelisted: %s  Invalid %s  Toplist: %s\n\n" \
        "$before_count" "$after_count" "$subdomains_count" "$total_whitelisted_count" \
        "$invalid_count" "$toplist_count"
}

# Function 'filter' logs the given entries and removes them from the $domains
# variable.
# Input:
#   $1: entries to process
#   $2: tag given to entries
#   --preserve: set flag to not remove the entries from $domains
# Output:
#   Number of entries that were passed
filter() {
    local entries="$1"
    local tag="$2"

    # Return if no entries passed
    [[ -s "$entries" ]] && return

    awk -v tag="$tag" '{print $0 " (" tag ")"}' <<< "$entries" >> filter_log.tmp
    log_event "$entries" "$tag"

    if [[ "$3" != '--preserve' ]]; then
        # Remove entries
        domains="$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$entries"))"
    fi

    # Return the number of entries
    wc -l <<< "$entries"
}

# Function 'send_telegram' sends a telegram notification with the given message.
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

# Function 'download_toplist' downloads the toplist and formats it.
# Output:
#   toplist.tmp
download_toplist() {
    [[ -f toplist.tmp ]] && return

    wget -qO - 'https://tranco-list.eu/top-1m.csv.zip' | gunzip - > toplist.tmp \
        || send_telegram "Error downloading toplist."

    awk -F ',' '{print $2}' toplist.tmp > temp && mv temp toplist.tmp

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

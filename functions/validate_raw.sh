#!/bin/bash

# Validates the entries in the raw file via a variety of checks and
# flags entries that require attention.

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly WHITELIST='config/whitelist.txt'
readonly BLACKLIST='config/blacklist.txt'
readonly TOPLIST='data/toplist.txt'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'
readonly WILDCARDS='data/wildcards.txt'
readonly REDUNDANT_DOMAINS='data/redundant_domains.txt'
readonly DOMAIN_LOG='config/domain_log.csv'

validate_raw() {
    domains="$(<"$RAW")"
    before_count="$(wc -l < "$RAW")"

    # Remove common subdomains
    domains_with_subdomains_count=0
    while read -r subdomain; do  # Loop through common subdomains
        # Find domains and skip to next subdomain if none found
        domains_with_subdomains="$(grep "^${subdomain}\." <<< "$domains")" \
            || continue

        # Count number of domains with common subdomains
        # Note wc -w is used here as wc -l for an empty variable seems to
        # always output 1
        domains_with_subdomains_count="$((
            domains_with_subdomains_count + $(wc -w <<< "$domains_with_subdomains")
            ))"

        # Keep only root domains
        domains="$(echo "$domains" | sed "s/^${subdomain}\.//" | sort -u)"
        sed "s/^${subdomain}\.//" "$RAW_LIGHT" | sort -u -o "$RAW_LIGHT"
        format_file "$RAW_LIGHT"

        # Collate subdomains for dead check
        printf "%s\n" "$domains_with_subdomains" >> subdomains.tmp
        # Collate root domains to exclude from dead check
        printf "%s\n" "$domains_with_subdomains" | sed "s/^${subdomain}\.//" >> root_domains.tmp

        awk '{print $0 " (subdomain)"}' <<< "$domains_with_subdomains" >> filter_log.tmp
        log_event "$domains_with_subdomains" subdomain
    done < "$SUBDOMAINS_TO_REMOVE"
    format_file subdomains.tmp
    format_file root_domains.tmp

    # Remove whitelisted domains, excluding blacklisted domains
    whitelisted_domains="$(comm -23 <(grep -Ff "$WHITELIST" <<< "$domains") "$BLACKLIST")"
    whitelisted_count="$(wc -w <<< "$whitelisted_domains")"
    if (( whitelisted_count > 0 )); then
        domains="$(comm -23 <(echo "$domains") <(echo "$whitelisted_domains"))"
        awk '{print $0 " (whitelisted)"}' <<< "$whitelisted_domains" >> filter_log.tmp
        log_event "$whitelisted_domains" whitelist
    fi

    # Remove domains that have whitelisted TLDs
    whitelisted_tld_domains="$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' <<< "$domains")"
    whitelisted_tld_count="$(wc -w <<< "$whitelisted_tld_domains")"
    if (( whitelisted_tld_count > 0 )); then
        domains="$(comm -23 <(echo "$domains") <(echo "$whitelisted_tld_domains"))"
        awk '{print $0 " (whitelisted TLD)"}' <<< "$whitelisted_tld_domains" >> filter_log.tmp
        log_event "$whitelisted_tld_domains" tld
    fi

    # Remove invalid entries and IP addresses. Punycode TLDs (.xn--*) are allowed
    invalid_entries="$(grep -vE '^[[:alnum:].-]+\.[[:alnum:]-]*[a-z][[:alnum:]-]{1,}$' <<< "$domains")"
    invalid_entries_count="$(wc -w <<< "$invalid_entries")"
    if (( invalid_entries_count > 0 )); then
        domains="$(comm -23 <(echo "$domains") <(echo "$invalid_entries"))"
        awk '{print $0 " (invalid)"}' <<< "$invalid_entries" >> filter_log.tmp
        log_event "$invalid_entries" invalid
    fi

    # Find potential redundant domains (domains with more than 1 period)
    # This is to prevent root domains from being false positive wildcards
    potential_redundant="$(grep '\..*\.' <<< "$domains")"

    # Strip potential redundant domains down to their root domains
    stripped_redundant="$(echo "$potential_redundant" \
        rev | awk -F '.' '{print $1 "." $2}' | rev | sort -u)"

    # Find wildcard domains by finding root domains already in the blocklist
    wildcard_domains="$(comm -12 <(echo "$domains") <(echo "$stripped_redundant"))"

    if [[ -n "$wildcard_domains" ]]; then
        # Collate wildcard domains to exclude from dead check
        printf "%s\n" "$wildcard_domains" >> wildcards.tmp
        format_file wildcards.tmp

        redundant_count=0
        # Get redundant domains
        while read -r wildcard; do  # Loop through wildcards
            # Find redundant domains via wildcard matching and skip to
            # next wildcard if none found
            redundant_domains="$(grep "\.${wildcard}$" <<< "$domains")" \
                || continue

            # Count number of redundant domains
            redundant_count="$((redundant_count + $(wc -w <<< "$redundant_domains")))"

            # Remove redundant domains
            domains="$(comm -23 <(echo "$domains") <(echo "$redundant_domains"))"

            # Collate redundant domains for dead check
            printf "%s\n" "$redundant_domains" >> redundant_domains.tmp

            awk '{print $0 " (redundant)"}' <<< "$redundant_domains" >> filter_log.tmp
            log_event "$redundant_domains" redundant
        done <<< "$wildcard_domains"
    fi
    format_file redundant_domains.tmp

    # Find matching domains in toplist, excluding blacklisted domains
    # Note domains found are not removed
    domains_in_toplist="$(comm -23 <(comm -12 <(echo "$domains") "$TOPLIST") "$BLACKLIST")"
    toplist_count="$(wc -w <<< "$domains_in_toplist")"
    if (( toplist_count > 0 )); then
        awk '{print $0 " (toplist)"}' \
            <<< "$domains_in_toplist" >> filter_log.tmp
        log_event "$domains_in_toplist" toplist
    fi

    # Exit if no filtering done
    [[ ! -f filter_log.tmp ]] && exit

    # Collate filtered wildcards
    if [[ -f wildcards.tmp ]]; then
        # Find wildcard domains in the filtered domains
        wildcards="$(comm -12 wildcards.tmp <(echo "$domains"))"

        # Collate filtered wildcards to exclude from dead check
        printf "%s\n" "$wildcards" >> "$WILDCARDS"
        # Collate filtered redundant domains for dead check
        grep -Ff <(echo "$wildcards") redundant_domains.tmp >> "$REDUNDANT_DOMAINS"

        format_file "$WILDCARDS"
        format_file "$REDUNDANT_DOMAINS"
    fi

    # Collate filtered subdomains and root domains
    if [[ -f root_domains.tmp ]]; then
        # Find root domains (subdomains stripped off) in the filtered domains
        root_domains="$(comm -12 root_domains.tmp <(echo "$domains"))"

        # Collate filtered root domains to exclude from dead check
        printf "%s\n" "$root_domains" >> "$ROOT_DOMAINS"
        # Collate filtered subdomains for dead check
        grep -Ff <(echo "$root_domains") subdomains.tmp >> "$SUBDOMAINS"

        format_file "$ROOT_DOMAINS"
        format_file "$SUBDOMAINS"
    fi

    # Print filter log
    printf "\n\e[1mProblematic domains (%s):\e[0m\n" "$(wc -l < filter_log.tmp)"
    sed 's/(toplist)/(toplist) - \o033[31mmanual verification required\o033[0m/' filter_log.tmp

    # Send telegram notification
    send_telegram "Problematic domains detected during validation check:\n$(<filter_log.tmp)"

    # Save changes to raw file and raw light file
    printf "%s\n" "$domains" > "$RAW"
    format_file "$RAW"
    comm -12 "$RAW" "$RAW_LIGHT" > light.tmp
    mv light.tmp "$RAW_LIGHT"

    total_whitelisted_count="$(( whitelisted_count + whitelisted_tld_count ))"
    after_count="$(wc -l < "$RAW")"
    printf "\nBefore: %s  After: %s  Subdomains: %s  Whitelisted: %s  Invalid %s  Redundant: %s  Toplist: %s\n\n" \
        "$before_count" "$after_count" "$domains_with_subdomains_count" "$total_whitelisted_count" \
        "$invalid_entries_count" "$redundant_count" "$toplist_count"
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

# Function 'log_event' logs domain processing events into the domain log.
#   $1: domains to log stored in a variable.
#   $2: event type (dead, whitelisted, etc.)
#   $3: source
log_event() {
    [[ -z "$1" ]] && return  # Return if no domains in variable
    local source='raw'
    printf "%s\n" "$1" | awk -v type="$2" -v source="$source" -v time="$(date -u +"%H:%M:%S %d-%m-%y")" \
        '{print time "," type "," $0 "," source}' >> "$DOMAIN_LOG"
}

# Function 'format_file' calls a shell wrapper to standardize the format
# of a file.
#   $1: file to format
format_file() {
    bash functions/tools.sh format "$1"
}

# Entry point

trap 'find . -maxdepth 1 -type f -name "*.tmp" -delete' EXIT

# Add new wildcards to the raw files
cat "$WILDCARDS" >> "$RAW"
cat "$WILDCARDS" >> "$RAW_LIGHT"

for file in config/* data/*; do
    format_file "$file"
done

validate_raw

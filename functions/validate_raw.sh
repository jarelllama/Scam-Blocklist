#!/bin/bash

# Validates the domains in the raw file via a variety of checks

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
TIME_FORMAT="$(date -u +"%H:%M:%S %d-%m-%y")"
readonly TIME_FORMAT

# Function 'validate_raw' stores the domains in the raw file in a variable and validates them
# via a variety of checks
validate_raw() {
    domains="$(<"$RAW")"
    before_count="$(wc -l < "$RAW")"

    # Remove common subdomains
    domains_with_subdomains_count=0
    while read -r subdomain; do  # Loop through common subdomains
        domains_with_subdomains="$(grep "^${subdomain}\." <<< "$domains")"
        [[ -z "$domains_with_subdomains" ]] && continue
        # Count number of domains with common subdomains
        domains_with_subdomains_count="$((domains_with_subdomains_count + $(wc -l <<< "$domains_with_subdomains")))"

        # Keep only root domains
        domains="$(printf "%s" "$domains" | sed "s/^${subdomain}\.//" | sort -u)"
        sed "s/^${subdomain}\.//" "$RAW_LIGHT" | sort -u -o "$RAW_LIGHT"
        format_file "$RAW_LIGHT"

        # Collate subdomains for dead check
        printf "%s\n" "$domains_with_subdomains" >> subdomains.tmp
        # Collate root domains to exclude from dead check
        printf "%s\n" "$domains_with_subdomains" | sed "s/^${subdomain}\.//" >> root_domains.tmp

        awk '{print $0 " (subdomain)"}' <<< "$domains_with_subdomains" >> filter_log.tmp
        log_event "$domains_with_subdomains" "subdomain"
    done < "$SUBDOMAINS_TO_REMOVE"
    format_file subdomains.tmp
    format_file root_domains.tmp

    # Remove whitelisted domains, excluding blacklisted domains
    whitelisted_domains="$(comm -23 <(grep -Ff "$WHITELIST" <<< "$domains") "$BLACKLIST")"
    whitelisted_count="$(wc -l <<< "$whitelisted_domains")"
    if [[ "$whitelisted_count" -gt 0 ]]; then
        domains="$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$whitelisted_domains"))"
        awk '{print $0 " (whitelisted)"}' <<< "$whitelisted_domains" >> filter_log.tmp
        log_event "$whitelisted_domains" "whitelist"
    fi

    # Remove domains that have whitelisted TLDs
    whitelisted_tld_domains="$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' <<< "$domains")"
    whitelisted_tld_count="$(wc -l <<< "$whitelisted_tld_domains")"
    if [[ "$whitelisted_tld_count" -gt 0 ]]; then
        domains="$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$whitelisted_tld_domains"))"
        awk '{print $0 " (whitelisted TLD)"}' <<< "$whitelisted_tld_domains" >> filter_log.tmp
        log_event "$whitelisted_tld_domains" "tld"
    fi

    # Remove invalid entries including IP addresses. This excludes punycode TLDs (.xn--*)
    invalid_entries="$(grep -vE '^[[:alnum:].-]+\.[[:alnum:]-]*[a-z][[:alnum:]-]{1,}$' <<< "$domains")"
    invalid_entries_count="$(wc -l <<< "$invalid_entries")"
    if [[ "$invalid_entries_count" -gt 0 ]]; then
        domains="$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$invalid_entries"))"
        awk '{print $0 " (invalid)"}' <<< "$invalid_entries" >> filter_log.tmp
        log_event "$invalid_entries" "invalid"
    fi

    # Remove redundant domains
    redundant_count=0
    while read -r domain; do  # Loop through each domain in the blocklist
        # Find redundant domains via wildcard matching
        redundant_domains="$(grep "\.${domain}$" <<< "$domains")"
        [[ -z "$redundant_domains" ]] && continue
        # Count number of redundant domains
        redundant_count="$((redundant_count + $(wc -l <<< "$redundant_domains")))"

        # Remove redundant domains
        domains="$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$redundant_domains"))"

        # Collate redundant domains for dead check
        printf "%s\n" "$redundant_domains" >> redundant_domains.tmp
        # Collate wildcard domains to exclude from dead check
        printf "%s\n" "$domain" >> wildcards.tmp

        awk '{print $0 " (redundant)"}' <<< "$redundant_domains" >> filter_log.tmp
        log_event "$redundant_domains" "redundant"
    done <<< "$domains"
    format_file redundant_domains.tmp
    format_file wildcards.tmp

    # Find matching domains in toplist, excluding blacklisted domains
    domains_in_toplist="$(comm -23 <(comm -12 <(printf "%s" "$domains") "$TOPLIST") "$BLACKLIST")"
    toplist_count="$(wc -l <<< "$domains_in_toplist")"
    if [[ "$toplist_count" -gt 0 ]]; then
        awk '{print $0 " (toplist) - \033[1;31mmanual removal required\033[0m"}' \
            <<< "$domains_in_toplist" >> filter_log.tmp
        log_event "$domains_in_toplist" "toplist"
    fi

    # Exit if no filtering done
    [[ ! -f filter_log.tmp ]] && exit 0
    sort -u filter_log.tmp -o filter_log.tmp

    # Collate filtered wildcards
    if [[ -f wildcards.tmp ]]; then
        # Find wildcard domains in the filtered domains
        wildcards="$(comm -12 wildcards.tmp <(printf "%s" "$domains"))"

        # Collate filtered wildcards to exclude from dead check
        printf "%s\n" "$wildcards" >> "$WILDCARDS"
         # Collate filtered redundant domains for dead check
        grep -Ff <(printf "%s" "$wildcards") redundant_domains.tmp >> "$REDUNDANT_DOMAINS"

        format_file "$WILDCARDS"
        format_file "$REDUNDANT_DOMAINS"
    fi

    # Collate filtered subdomains and root domains
    if [[ -f root_domains.tmp ]]; then
        # Find root domains (subdomains stripped off) in the filtered domains
        root_domains="$(comm -12 root_domains.tmp <(printf "%s" "$domains"))"

        # Collate filtered root domains to exclude from dead check
        printf "%s\n" "$root_domains" >> "$ROOT_DOMAINS"
        # Collate filtered subdomains for dead check
        grep -Ff <(printf "%s" "$root_domains") subdomains.tmp >> "$SUBDOMAINS"

        format_file "$ROOT_DOMAINS"
        format_file "$SUBDOMAINS"
    fi

    printf "\n\e[1mProblematic domains (%s):\e[0m\n" "$(wc -l < filter_log.tmp)"
    cat filter_log.tmp

    printf "%s\n" "$domains" > "$RAW"
    format_file "$RAW"
    # Remove filtered domains from light file
    comm -12 "$RAW" "$RAW_LIGHT" > light.tmp && mv light.tmp "$RAW_LIGHT"

    total_whitelisted_count="$((whitelisted_count + whitelisted_tld_count))"
    after_count="$(wc -l < "$RAW")"
    printf "\nBefore: %s  After: %s  Subdomains: %s  Whitelisted: %s  Invalid %s  Redundant: %s  Toplist: %s\n\n" \
        "$before_count" "$after_count" "$domains_with_subdomains_count" "$total_whitelisted_count" "$invalid_entries_count" "$redundant_count" "$toplist_count"

    exit 1
}

# Function 'log_event' logs domain processing events into the domain log
# $1: domains to log stored in a variable
# $2: event type (dead, whitelisted, etc.)
log_event() {
    printf "%s\n" "$1" | awk -v type="$2" -v source=raw -v time="$TIME_FORMAT" \
        '{print time "," type "," $0 "," source}' >> "$DOMAIN_LOG"
}

# Function 'format_file' is a shell wrapper to standardize the format of a file
# $1: file to format
format_file() {
    bash functions/tools.sh format "$1"
}

trap 'find . -maxdepth 1 -type f -name "*.tmp" -delete' EXIT

# Format files in the config and data directory
for file in config/* data/*; do
    format_file "$file"
done

# Add new wildcards to the raw files
cat "$WILDCARDS" >> "$RAW"
cat "$WILDCARDS" >> "$RAW_LIGHT"
format_file "$RAW"
format_file "$RAW_LIGHT"

validate_raw

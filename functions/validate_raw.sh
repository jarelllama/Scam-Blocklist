#!/bin/bash
#
# Validates the domains in the raw file via a variety of checks.

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

function validate_raw {
    # Add new wildcards to the raw files
    cat "$WILDCARDS" >> "$RAW"
    cat "$WILDCARDS" >> "$RAW_LIGHT"
    format_files "$RAW"
    format_files "$RAW_LIGHT"

    domains="$(<"$RAW")"
    before_count="$(wc -l < "$RAW")"
    touch filter_log.tmp

    # Remove common subdomains
    domains_with_subdomains_count=0
    while read -r subdomain; do  # Loop through common subdomains
        domains_with_subdomains="$(grep "^${subdomain}\." <<< "$domains")"
        [[ -z "$domains_with_subdomains" ]] && continue

        # Count number of domains with common subdomains
        domains_with_subdomains_count="$((
            domains_with_subdomains_count + $(wc -w <<< "$domains_with_subdomains")
            ))"

        # Keep only root domains
        domains="$(printf "%s" "$domains" | sed "s/^${subdomain}\.//" | sort -u)"

        # Keep only root domains in raw light file
        sed "s/^${subdomain}\.//" "$RAW_LIGHT" | sort -u -o "$RAW_LIGHT"
        format_files "$RAW_LIGHT"

        # Collate subdomains for dead check
        printf "%s\n" "$domains_with_subdomains" >> subdomains.tmp

        # Collate root domains to exclude from dead check
        printf "%s\n" "$domains_with_subdomains" | sed "s/^${subdomain}\.//" >> root_domains.tmp

        awk '{print $0 " (subdomain)"}' <<< "$domains_with_subdomains" >> filter_log.tmp
        log_event "$domains_with_subdomains" "subdomain"
    done < "$SUBDOMAINS_TO_REMOVE"
    format_files subdomains.tmp
    format_files root_domains.tmp

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
        redundant_count="$((redundant_count + $(wc -w <<< "$redundant_domains")))"

        # Remove redundant domains
        domains="$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$redundant_domains"))"

        # Collate redundant domains for dead check
        printf "%s\n" "$redundant_domains" >> redundant_domains.tmp

        # Collate wildcard domains to exclude from dead check
        printf "%s\n" "$domain" >> wildcards.tmp

        awk '{print $0 " (redundant)"}' <<< "$redundant_domains" >> filter_log.tmp
        log_event "$redundant_domains" "redundant"
    done <<< "$domains"
    format_files redundant_domains.tmp
    format_files wildcards.tmp

    # Find matching domains in toplist, excluding blacklisted domains
    domains_in_toplist="$(comm -23 <(comm -12 <(printf "%s" "$domains") "$TOPLIST") "$BLACKLIST")"
    toplist_count="$(wc -l <<< "$domains_in_toplist")"
    if [[ "$toplist_count" -gt 0 ]]; then
        awk '{print $0 " (toplist) - \033[1;31mmanual removal required\033[0m"}' \
            <<< "$domains_in_toplist" >> filter_log.tmp
        log_event "$domains_in_toplist" "toplist"
    fi

    [[ ! -s filter_log.tmp ]] && return
    sort -u filter_log.tmp -o filter_log.tmp

    # Collate filtered wildcards
    if [[ -f wildcards.tmp ]]; then
        # Find wildcard domains in the filtered domains
        wildcards="$(comm -12 wildcards.tmp <(printf "%s" "$domains"))"
        # Collate filtered wildcards to exclude from dead check
        printf "%s\n" "$wildcards" >> "$WILDCARDS"
         # Collate filtered redundant domains for dead check
        grep -Ff <(printf "%s" "$wildcards") redundant_domains.tmp >> "$REDUNDANT_DOMAINS"
        format_files "$WILDCARDS"
        format_files "$REDUNDANT_DOMAINS"
    fi

    # Collate filtered subdomains and root domains
    if [[ -f root_domains.tmp ]]; then
        root_domains="$(comm -12 root_domains.tmp <(printf "%s" "$domains"))"  # Retrieve filtered root domains
        printf "%s\n" "$root_domains" >> "$ROOT_DOMAINS"  # Collate filtered root domains to exclude from dead check
        grep -Ff <(printf "%s" "$root_domains") subdomains.tmp >> "$SUBDOMAINS"  # Collate filtered subdomains for dead check
        format_files "$ROOT_DOMAINS" && format_files "$SUBDOMAINS"
    fi

    printf "\n\e[1mProblematic domains (%s):\e[0m\n" "$(wc -l < filter_log.tmp)"
    cat filter_log.tmp  # Print filter log
    printf "%s\n" "$domains" > "$RAW"  # Save changes to blocklist
    format_files "$RAW"
    total_whitelisted_count="$((whitelisted_count + whitelisted_tld_count))"  # Calculate sum of whitelisted domains
    after_count="$(wc -l < "$RAW")"  # Count number of domains after filtering
    printf "\nBefore: %s  After: %s  Subdomains: %s  Whitelisted: %s  Invalid %s  Redundant: %s  Toplist: %s\n\n" "$before_count" "$after_count" "$domains_with_subdomains_count" "$total_whitelisted_count" "$invalid_entries_count" "$redundant_count" "$toplist_count"
}

function update_light_file {
    comm -12 "$RAW" "$RAW_LIGHT" > light.tmp && mv light.tmp "$RAW_LIGHT"  # Keep only domains found in full raw file
}

# Function 'log_event' logs domain processing events into the domain log
# $1: domains to log stored in a variable
# $2: event type (dead, whitelisted, etc.)
function log_event {
    printf "%s\n" "$1" | awk -v type="$2" -v time="$TIME_FORMAT" '{print time "," type "," $0 ",raw"}' >> "$DOMAIN_LOG"
}

function format_files {
    bash functions/tools.sh "format" "$1"
}

trap ' find . -maxdepth 1 -type f -name "*.tmp" -delete' EXIT

# Format files in the config and data directory
for file in config/* data/*; do
    format_files "$file"
done

validate_raw
update_light_file

# Exit with error if blocklist required filtering
[[ -s filter_log.tmp ]] && exit 1 || exit 0

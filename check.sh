#!/bin/bash
raw_file='data/raw.txt'
raw_light_file='data/raw_light.txt'
domain_log='config/domain_log.csv'
whitelist_file='config/whitelist.txt'
blacklist_file='config/blacklist.txt'
toplist_file='data/toplist.txt'
root_domains_file='data/root_domains.txt'
subdomains_file='data/subdomains.txt'
subdomains_to_remove_file='config/subdomains.txt'
wildcards_file='data/wildcards.txt'
redundant_domains_file='data/redundant_domains.txt'
time_format=$(date -u +"%H:%M:%S %d-%m-%y")

function main {
    for file in config/* data/*; do  # Format files in the config and data directory
        format_list "$file"
    done
    check_raw_file
    update_light_file
    [[ -s filter_log.tmp ]] && exit 1 || exit 0  # Exit with error if blocklist required filtering
}

function check_raw_file {
    # Add new wildcards to the raw files
    cat "$wildcards_file" >> "$raw_file"
    cat "$wildcards_file" >> "$raw_light_file"
    format_list "$raw_file" && format_list "$raw_light_file"
    domains=$(<"$raw_file")
    before_count=$(wc -l < "$raw_file")
    touch filter_log.tmp

    # Remove common subdomains
    domains_with_subdomains_count=0  # Initialize domains with common subdomains count
    while read -r subdomain; do  # Loop through common subdomains
        domains_with_subdomains=$(grep "^${subdomain}\." <<< "$domains")  # Find domains with common subdomains
        [[ -z "$domains_with_subdomains" ]] && continue  # Skip to next subdomain if no matches found
        # Count number of domains with common subdomains
        domains_with_subdomains_count=$((domains_with_subdomains_count + $(wc -w <<< "$domains_with_subdomains")))
        # Keep only root domains
        domains=$(printf "%s" "$domains" | sed "s/^${subdomain}\.//" | sort -u)
        # Keep only root domains in raw light file
        sed "s/^${subdomain}\.//" "$raw_light_file" | sort -u -o "$raw_light_file"
        format_list "$raw_light_file"
        # Collate subdomains for dead check
        printf "%s\n" "$domains_with_subdomains" >> subdomains.tmp
        # Collate root domains to exclude from dead check
        printf "%s\n" "$domains_with_subdomains" | sed "s/^${subdomain}\.//" >> root_domains.tmp
        awk 'NF {print $0 " (subdomain)"}' <<< "$domains_with_subdomains" >> filter_log.tmp
        log_event "$domains_with_subdomains" "subdomain"
    done < "$subdomains_to_remove_file"
    format_list subdomains.tmp && format_list root_domains.tmp

    # Remove whitelisted domains, excluding blacklisted domains
    whitelisted_domains=$(comm -23 <(grep -Ff "$whitelist_file" <<< "$domains") "$blacklist_file")
    whitelisted_count=$(wc -w <<< "$whitelisted_domains")
    if [[ "$whitelisted_count" -gt 0 ]]; then
        domains=$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$whitelisted_domains"))
        awk 'NF {print $0 " (whitelisted)"}' <<< "$whitelisted_domains" >> filter_log.tmp
        log_event "$whitelisted_domains" "whitelist"
    fi

    # Remove domains that have whitelisted TLDs
    whitelisted_tld_domains=$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' <<< "$domains")
    whitelisted_tld_count=$(wc -w <<< "$whitelisted_tld_domains")
    if [[ "$whitelisted_tld_count" -gt 0 ]]; then
        domains=$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$whitelisted_tld_domains"))
        awk 'NF {print $0 " (whitelisted TLD)"}' <<< "$whitelisted_tld_domains" >> filter_log.tmp
        log_event "$whitelisted_tld_domains" "tld"
    fi

    # Remove invalid entries including IP addresses. This excludes punycode TLDs (.xn--*)
    invalid_entries=$(grep -vE '^[[:alnum:].-]+\.[[:alnum:]-]*[a-z][[:alnum:]-]{1,}$' <<< "$domains")
    invalid_entries_count=$(wc -w <<< "$invalid_entries")
    if [[ "$invalid_entries_count" -gt 0 ]]; then
        domains=$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$invalid_entries"))
        awk 'NF {print $0 " (invalid)"}' <<< "$invalid_entries" >> filter_log.tmp
        log_event "$invalid_entries" "invalid"
    fi

    # Remove redundant domains
    redundant_count=0  # Initialize redundant domains count
    while read -r domain; do  # Loop through each domain in the blocklist
        redundant_domains=$(grep "\.${domain}$" <<< "$domains")  # Find redundant domains via wildcard matching
        [[ -z "$redundant_domains" ]] && continue  # Skip to next domain if no matches found
        # Count number of redundant domains
        redundant_count=$((redundant_count + $(wc -w <<< "$redundant_domains")))
        # Remove redundant domains
        domains=$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$redundant_domains"))
        # Collate redundant domains for dead check
        printf "%s\n" "$redundant_domains" >> redundant_domains.tmp
        # Collate wildcard domains to exclude from dead check
        printf "%s\n" "$domain" >> wildcards.tmp
        awk 'NF {print $0 " (redundant)"}' <<< "$redundant_domains" >> filter_log.tmp
        log_event "$redundant_domains" "redundant"
    done <<< "$domains"
    format_list redundant_domains.tmp && format_list wildcards.tmp

    # Find matching domains in toplist, excluding blacklisted domains
    domains_in_toplist=$(comm -23 <(comm -12 <(printf "%s" "$domains") "$toplist_file") "$blacklist_file")
    toplist_count=$(wc -w <<< "$domains_in_toplist")
    if [[ "$toplist_count" -gt 0 ]]; then
        awk 'NF {print "! " $0 " (toplist) - manual removal required"}' <<< "$domains_in_toplist" >> filter_log.tmp
        log_event "$domains_in_toplist" "toplist"
    fi

    sed '/^$/d' filter_log.tmp | sort -u -o filter_log.tmp  # Remove empty lines, sort and remove duplicates (note filter log has whitespaces)
    [[ ! -s filter_log.tmp ]] && return  # Return if no domains were filtered

    # Collate filtered wildcards
    if [[ -f wildcards.tmp ]]; then
        wildcards=$(comm -12 wildcards.tmp <(printf "%s" "$domains"))  # Retrieve filtered wildcard domains
        printf "%s\n" "$wildcards" >> "$wildcards_file"  # Collate filtered wildcards
        grep -Ff <(printf "%s" "$wildcards") redundant_domains.tmp >> "$redundant_domains_file"  # Collate filtered redundant domains for dead check
        format_list "$wildcards_file" && format_list "$redundant_domains_file"
    fi

    # Collate filtered subdomains and root domains
    if [[ -f root_domains.tmp ]]; then
        root_domains=$(comm -12 root_domains.tmp <(printf "%s" "$domains"))  # Retrieve filtered root domains
        printf "%s\n" "$root_domains" >> "$root_domains_file"  # Collate filtered root domains to exclude from dead check
        grep -Ff <(printf "%s" "$root_domains") subdomains.tmp >> "$subdomains_file"  # Collate filtered subdomains for dead check
        format_list "$root_domains_file" && format_list "$subdomains_file"
    fi

    printf "\nProblematic domains (%s):\n" "$(wc -l < filter_log.tmp)"
    cat filter_log.tmp
    printf "%s\n" "$domains" > "$raw_file"  # Save changes to blocklist
    format_list "$raw_file"
    total_whitelisted_count=$((whitelisted_count + whitelisted_tld_count))  # Calculate sum of whitelisted domains
    after_count=$(wc -l < "$raw_file")  # Count number of domains after filtering
    printf "\nBefore: %s  After: %s  Subdomains: %s  Whitelisted: %s  Invalid %s  Redundant: %s  Toplist: %s\n\n" "$before_count" "$after_count" "$domains_with_subdomains_count" "$total_whitelisted_count" "$invalid_entries_count" "$redundant_count" "$toplist_count"
}

function update_light_file {
    comm -12 "$raw_file" "$raw_light_file" > light.tmp && mv light.tmp "$raw_light_file"  # Keep only domains found in full raw file
}

function log_event {
    # Log domain events
    printf "%s\n" "$1" | awk -v type="$2" -v time="$time_format" '{print time "," type "," $0 ",raw"}' >> "$domain_log"
}

function format_list {
    bash data/tools.sh "format" "$1"
}

function cleanup {
    find . -maxdepth 1 -type f -name "*.tmp" -delete
}

trap cleanup EXIT
main

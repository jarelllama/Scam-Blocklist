#!/bin/bash
raw_file='data/raw.txt'
domain_log='data/domain_log.csv'
whitelist_file='config/whitelist.txt'
blacklist_file='config/blacklist.txt'
toplist_file='data/processing/toplist.txt'
root_domains_file='data/processing/root_domains.txt'
subdomains_file='data/processing/subdomains.txt'
subdomains_to_remove_file='config/subdomains.txt'
wildcards_file='data/processing/wildcards.txt'
redundant_domains_file='data/processing/redundant_domains.txt'
time_format="$(date -u +"%H:%M:%S %d-%m-%y")"
toplist_url='https://tranco-list.eu/top-1m.csv.zip'

function main {
    for file in config/* data/* data/processing/*; do  # Format files in the config and data directory
        format_list "$file"
    done
    retrieve_toplist
    check_raw_file
}

function retrieve_toplist {
    wget -q -O - "$toplist_url" | gunzip - > toplist.tmp  # Download and unzip toplist to temp file
    awk -F ',' '{print $2}' toplist.tmp > "$toplist_file"  # Format toplist to keep only domains
    format_list "$toplist_file"
}

function check_raw_file {
    domains=$(<"$raw_file")
    before_count=$(wc -w <<< "$domains")
    touch filter_log.tmp  # Initialize temp filter log file

    domains_with_subdomains_count=0  # Initiliaze domains with common subdomains count
    # Remove common subdomains
    while read -r subdomain; do  # Loop through common subdomains
        domains_with_subdomains=$(grep "^${subdomain}\." <<< "$domains")  # Find domains with common subdomains
        [[ -z "$domains_with_subdomains" ]] && continue  # Skip to next subdomain if no matches found
        # Count number of domains with common subdomains
        domains_with_subdomains_count=$((domains_with_subdomains_count + $(wc -w <<< "$domains_with_subdomains")))
        # Keep only root domains
        domains=$(printf "%s" "$domains" | sed "s/^${subdomain}\.//" | sort -u)
        # Collate subdomains for dead check
        printf "%s\n" "$domains_with_subdomains" >> subdomains.tmp
        # Collate root domains to exclude from dead check
        printf "%s\n" "$domains_with_subdomains" | sed "s/^${subdomain}\.//" >> root_domains.tmp
        awk 'NF {print $0 " (subdomain)"}' <<< "$domains_with_subdomains" >> filter_log.tmp
        log_event "$domains_with_subdomains" "subdomain"
    done < "$subdomains_to_remove_file"
    format_list subdomains.tmp
    format_list root_domains.tmp

    # Remove whitelisted domains, excluding blacklisted domains
    whitelisted_domains=$(comm -23 <(grep -Ff "$whitelist_file" <<< "$domains") "$blacklist_file")
    whitelisted_count=$(wc -w <<< "$whitelisted_domains")  # Count number of whitelisted domains
    if [[ "$whitelisted_count" -gt 0 ]]; then
        domains=$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$whitelisted_domains"))
        awk 'NF {print $0 " (whitelisted)"}' <<< "$whitelisted_domains" >> filter_log.tmp
        log_event "$whitelisted_domains" "whitelist"
    fi

    # Remove domains that have whitelisted TLDs
    whitelisted_tld_domains=$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' <<< "$domains")
    whitelisted_tld_count=$(wc -w <<< "$whitelisted_tld_domains")  # Count number of domains with whitelisted TLDs
    if [[ "$whitelisted_tld_count" -gt 0 ]]; then
        domains=$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$whitelisted_tld_domains"))
        awk 'NF {print $0 " (whitelisted TLD)"}' <<< "$whitelisted_tld_domains" >> filter_log.tmp
        log_event "$whitelisted_tld_domains" "tld"
    fi

    # Remove invalid entries including IP addresses This excludes punycode TLDs (.xn--*)
    invalid_entries=$(grep -vE '^[[:alnum:].-]+\.[[:alnum:]-]*[[:alpha:]][[:alnum:]-]{1,}$' <<< "$domains")
    invalid_entries_count=$(wc -w <<< "$invalid_entries")
    if [[ "$invalid_entries_count" -gt 0 ]]; then
        domains=$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$invalid_entries"))
        awk 'NF {print $0 " (invalid)"}' <<< "$invalid_entries" >> filter_log.tmp
        log_event "$invalid_entries" "invalid"
    fi

    redundant_domains_count=0  # Initialize redundant domains count
    # Remove redundant domains
    while read -r domain; do  # Loop through each domain in the blocklist
        redundant_domains=$(grep "\.${domain}$" <<< "$domains")  # Find redundant domains via wildcard matching
        [[ -z "$redundant_domains" ]] && continue  # Skip to next domain if no matches found
        # Count number of redundant domains
        redundant_domains_count=$((redundant_domains_count + $(wc -w <<< "$redundant_domains")))
        # Remove redundant domains
        domains=$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$redundant_domains"))
        # Collate redundant domains for dead check
        printf "%s\n" "$redundant_domains" >> redundant_domains.tmp
        # Collate wilcard domains to exclude from dead check
        printf "%s\n" "$domain" >> wildcards.tmp
        awk 'NF {print $0 " (redundant)"}' <<< "$redundant_domains" >> filter_log.tmp
        log_event "$redundant_domains" "redundant"
    done <<< "$domains"
    format_list redundant_domains.tmp
    format_list wildcards.tmp

    # Find matching domains in toplist, excluding blacklisted domains
    domains_in_toplist=$(comm -23 <(comm -12 <(printf "%s" "$domains") "$toplist_file") "$blacklist_file")
    in_toplist_count=$(wc -w <<< "$domains_in_toplist")  # Count number of domains found in toplist
    if [[ "$in_toplist_count" -gt 0 ]]; then
        awk 'NF {print $0 " (toplist) - manual removal required"}' <<< "$domains_in_toplist" >> filter_log.tmp
        log_event "$domains_in_toplist" "toplist"
    fi

    tr -s '\n' < filter_log.tmp | sort -u > temp.tmp && mv temp.tmp filter_log.tmp  # Remove empty lines, sort and remove duplicates (note filter log has whitespaces)
    [[ ! -s filter_log.tmp ]] && exit  # Exit if no domains were filtered

    # Collate unfiltered wildcards
    if [[ -f wildcards.tmp ]]; then
        wildcards=$(comm -12 wildcards.tmp <(printf "%s" "$domains"))  # Retrieve unfiltered wildcard domains
        printf "%s\n" "$wildcards" >> "$wildcards_file" # Add the unfiltered wildcards domains to the wildcards file
        grep -Ff <(printf "%s" "$wildcards") redundant_domains.tmp >> "$redundant_domains_file" # Retrieve and add unfiltered redundant domains to redundant domains file
        format_list "$wildcards_file"
        format_list "$redundant_domains_file"
    fi
    # Collate unfiltered subdomains and root domains
    if [[ -f root_domains.tmp ]]; then
        root_domains=$(comm -12 root_domains.tmp <(printf "%s" "$domains"))  # Retrieve unfiltered root domains
        printf "%s\n" "$root_domains" >> "$root_domains_file"  # Add the unfiltered root domains to the root domains file
        grep -Ff <(printf "%s" "$root_domains") subdomains.tmp >> "$subdomains_file" # Retrieve and add unfiltered subdomains to subdomains file
        format_list "$root_domains_file"
        format_list "$subdomains_file"
    fi

    printf "\nProblematic domains (%s):\n" "$(wc -l < filter_log.tmp)"
    cat filter_log.tmp
    printf "%s\n" "$domains" > "$raw_file"  # Save changes to blocklist
    format_list "$raw_file"

    total_whitelisted_count=$((whitelisted_count + whitelisted_tld_count))  # Calculate sum of whitelisted domains
    after_count=$(wc -w <<< "$domains")  # Count number of domains after filtering
    printf "\nBefore: %s  After: %s  Subdomains: %s  Whitelisted: %s  Invalid %s  Redundant: %s  Toplist: %s\n\n" "$before_count" "$after_count" "$domains_with_subdomains_count" "$total_whitelisted_count" "$invalid_entries_count" "$redundant_domains_count" "$in_toplist_count"

    [[ -s filter_log.tmp ]] && exit 1 || exit 0 # Exit with error if the blocklist required filtering
}

function log_event {
    # Log domain processing events
    printf "%s\n" "$1" | awk -v type="$2" -v time="$time_format" '{print time "," type "," $0 ",raw"}' >> "$domain_log"
}

function format_list {
    [[ -f "$1" ]] || return  # Return if file does not exist
    if [[ "$1" == *.csv ]]; then  # If file is a CSV file, do not sort
        sed -i 's/\r//; /^$/d' "$1"
        return
    elif [[ "$1" == *dead_domains_file* ]]; then  # Do not sort the dead domains file
        tr -d ' \r' < "$1" | tr -s '\n' | awk '!seen[$0]++' > "${1}.tmp" && mv "${1}.tmp" "$1"
        return
    fi
    # Remove whitespaces, carriage return characters, empty lines, sort and remove duplicates
    tr -d ' \r' < "$1" | tr -s '\n' | sort -u > "${1}.tmp" && mv "${1}.tmp" "$1"
}

function cleanup {
    find . -maxdepth 1 -type f -name "*.tmp" -delete
}

trap cleanup EXIT
main

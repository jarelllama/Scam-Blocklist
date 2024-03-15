#!/bin/bash
raw_file='data/raw.txt'
toplist_file='data/toplist.txt'
domain_log='data/domain_log.csv'
whitelist_file='config/whitelist.txt'
blacklist_file='config/blacklist.txt'
subdomains_file='config/subdomains.txt'
wildcards_file='data/wildcards.txt'
time_format="$(TZ=Asia/Singapore date +"%H:%M:%S %d-%m-%y")"
toplist_url='https://tranco-list.eu/top-1m.csv.zip'

function main {
    for file in config/* data/*; do  # Format files in the config and data directory
        format_list "$file"
    done
    retrieve_toplist
    check_raw_file
}

function retrieve_toplist {
    wget -q -O - "$toplist_url" | gunzip - > "${toplist_file}.tmp"  # Download and unzip toplist to temp file
    awk -F ',' '{print $2}' "${toplist_file}.tmp" > "$toplist_file"  # Format toplist to keep only domains
    format_list "$toplist_file"
}

function check_raw_file {
    domains=$(<"$raw_file")
    before_count=$(wc -w <<< "$domains")
    touch filter_log.tmp  # Initialize temp filter log file

    domains_with_subdomains_count=0  # Initiliaze domains with common subdomains count
    # Remove common subdomains
    while read -r subdomain; do  # Loop through common subdomains
        domains_with_subdomains=$(grep "^${subdomain}\." <<< "$domains")
        [[ -z "$domains_with_subdomains" ]] && continue  # Skip to next subdomain if no matches found
        # Count number of domains with common subdomains
        domains_with_subdomains_count=$((domains_with_subdomains_count + $(wc -w <<< "$domains_with_subdomains")))
        domains=$(printf "%s" "$domains" | sed "s/^${subdomain}\.//" | sort -u)  # Remove the subdomain, keeping only the root domain, sort and remove duplicates
        awk 'NF {print $0 " (subdomain)"}' <<< "$domains_with_subdomains" >> filter_log.tmp
        log_event "$domains_with_subdomains" "subdomain"
    done < "$subdomains_file"

    # Remove whitelisted domains, excluding blacklisted domains
    whitelisted_domains=$(grep -Ff "$whitelist_file" <<< "$domains" | grep -vxFf "$blacklist_file")
    whitelisted_count=$(wc -w <<< "$whitelisted_domains")  # Count number of whitelisted domains
    if [[ whitelisted_count -gt 0 ]]; then  # Check if whitelisted domains were found
        domains=$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$whitelisted_domains"))
        awk 'NF {print $0 " (whitelisted)"}' <<< "$whitelisted_domains" >> filter_log.tmp
        log_event "$whitelisted_domains" "whitelist"
    fi
    
    # Remove domains that have whitelisted TLDs
    whitelisted_TLD_domains=$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' <<< "$domains")
    whitelisted_TLD_count=$(wc -w <<< "$whitelisted_TLD_domains")  # Count number of domains with whitelisted TLDs
    if [[ whitelisted_TLD_count -gt 0 ]]; then  # Check if domains with whitelisted TLDs were found
        domains=$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$whitelisted_TLD_domains"))
        awk 'NF {print $0 " (whitelisted TLD)"}' <<< "$whitelisted_TLD_domains" >> filter_log.tmp
        log_event "$whitelisted_TLD_domains" "tld"
    fi

    redundant_domains_count=0  # Initialize redundant domains count
    # Remove redundant domains
    while read -r domain; do  # Loop through each domain in the blocklist
        # Find redundant domains via wildcard matching
        redundant_domains=$(grep "\.${domain}$" <<< "$domains")
        [[ -z "$redundant_domains" ]] && continue  # Skip to next domain if no matches found
        # Count number of redundant domains
        redundant_domains_count=$((redundant_domains_count + $(wc -w <<< "$redundant_domains")))
        domains=$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$redundant_domains"))
        awk 'NF {print $0 " (redundant)"}' <<< "$redundant_domains" >> filter_log.tmp
        log_event "$redundant_domains" "redundant"
        log_event "$domain" "wildcard"
        printf "%s\n" "$domain" >> "$wildcards_file"  # Collate the wilcard domains into a file
    done <<< "$domains"
    format_list "$wildcards_file"

    # Find matching domains in toplist, excluding blacklisted domains
    domains_in_toplist=$(comm -12 <(printf "%s" "$domains") "$toplist_file" | grep -vxFf "$blacklist_file")
    in_toplist_count=$(wc -w <<< "$domains_in_toplist")  # Count number of domains found in toplist
    if [[ in_toplist_count -gt 0 ]]; then  # Check if domains were found in toplist
        awk 'NF {print $0 " (toplist) - manual removal required"}' <<< "$domains_in_toplist" >> filter_log.tmp
        log_event "$domains_in_toplist" "toplist"
    fi

    [[ -s filter_log.tmp ]] || save_and_exit 0  # Exit if no domains were filtered

    sleep 0.5
    printf "\nProblematic domains (%s):\n" "$(wc -l < filter_log.tmp)"
    sleep 0.5
    cat filter_log.tmp
    printf "%s" "$domains" > "$raw_file"  # Save changes to blocklist
    format_list "$raw_file"

    total_whitelisted_count=$((whitelisted_count + whitelisted_TLD_count))  # Calculate sum of whitelisted domains
    after_count=$(wc -w <<< "$domains")  # Count number of domains after filtering
    printf "\nBefore: %s  After: %s  Subdomains: %s  Whitelisted: %s  Redundant: %s  Toplist: %s\n\n" "$before_count" "$after_count" "$domains_with_subdomains_count" "$total_whitelisted_count" "$redundant_domains_count" "$in_toplist_count"
    save_and_exit 1  # Exit with error if the blocklist required filtering
}

function log_event {
    # Log domain processing events
    sed -i 's/\r$//' "$domain_log"  # Remove carriage return characters 
    printf "%s" "$1" | awk -v event="$2" -v time="$time_format" '{print time "," event "," $0 ",raw"}' >> "$domain_log"
}

function format_list {
    # If file is a CSV file, do not sort
    if [[ "$1" == *.csv ]]; then
        sed -i 's/\r$//' "$1"  
        return
    fi
    # Format carriage return characters, remove empty lines, sort and remove duplicates
    tr -d '\r' < "$1" | sed '/^$/d' | sort -u > "${1}.tmp" && mv "${1}.tmp" "$1"
}

function save_and_exit {
    [[ -f filter_log.tmp ]] && rm filter_log.tmp  # Delete temp filter log file
    exit_code="$1"
    # If running locally, exit without pushing changes to repository
    if [[ "$CI" != true ]]; then
        sleep 0.5
        printf "\nScript is running locally. No changes were pushed.\n"
        exit "$exit_code"
    fi
    git add .
    git commit -m "List maintenance"
    git push -q
    exit "$exit_code"
}

main

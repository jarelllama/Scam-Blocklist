#!/bin/bash
raw_file='data/raw.txt'
toplist_file='data/toplist.txt'
search_log='data/search_log.csv'
domain_log='data/domain_log.csv'
search_terms_file='config/search_terms.csv'
whitelist_file='config/whitelist.txt'
blacklist_file='config/blacklist.txt'
subdomains_file='config/subdomains.txt'
wildcards_file='data/wildcards.txt'
dead_domains_file='data/dead_domains.txt'
time_format="$(TZ=Asia/Singapore date +"%H:%M:%S %d-%m-%y")"
search_url='https://customsearch.googleapis.com/customsearch/v1'

# Find potential malicious hosting domains
# grep '\..*\.' raw.txt | awk -F '.' '{print $2"."$3}' | sort -u

# If running locally, use locally stored secrets instead of environment variables
if [[ "$CI" != true ]]; then
    search_id=$(<secrets/search_id)
    search_api_key=$(<secrets/search_api_key)
fi

function main {
    command -v csvstat &> /dev/null || pip install -q csvkit  # Install cvstat
    command -v jq &> /dev/null || apt-get install -yqq jq  # Install jq
    for file in config/* data/*; do  # Format files in the config and data directory
        format_list "$file"
    done

    # Retrieve domains using search terms only if there are no temporary search results files
    if ! ls data/search_term_*.tmp &> /dev/null; then
        retrieve_search_terms
        merge_domains
        exit
    fi

    printf "\nUsing existing list of retrieved domains.\n\n"
    for temp_search_results_file in data/search_term_*.tmp; do  # Loop through each temp search results file
        search_term=${temp_search_results_file#*search_term_}  # Remove header from file name
        search_term=${search_term%.tmp}  # Remove file extension from file name
        pending_domains=$(<"$temp_search_results_file")
        process_domains "$search_term" "$pending_domains"
    done
    merge_domains
}

function retrieve_search_terms {
    printf "\nRetrieving domains from search terms...\n\n"
    csvgrep -c 2 -m 'y' -i "$search_terms_file" | csvcut -c 1 | csvformat -U 1 | tail +2 |  # Filter out unused search terms
        while read -r search_term; do  # Loop through search terms
            retrieve_domains "$search_term"  # Pass the search term to the domain retrieval function
        done
}

function retrieve_domains {
    search_term="${1//\"/}"  # Remove quotes from search term before encoding
    encoded_search_term=$(printf "%s" "$search_term" | sed 's/[^[:alnum:]]/%20/g')  # Replace whitespaces and non-alphanumeric characters with '%20'
    for start in {1..100..10}; do  # Loop through each page of results (max of 100 results)
        query_params="cx=${search_id}&key=${search_api_key}&exactTerms=${encoded_search_term}&start=${start}&excludeTerms=scam&filter=0"
        page_results=$(curl -s "${search_url}?${query_params}")
        jq -e '.items' &> /dev/null <<< "$page_results" || break # Break out of loop when there are no more results 
        jq -r '.items[].link' <<< "$page_results" >> collated_page_results.tmp  # Collate all pages of results
    done

    # Skip to next search term if no results retrieved
    if [[ ! -f collated_page_results.tmp ]]; then
        log_search_term "$search_term" "0" "0" "0" "0" "0" "0" ""
        return
    fi
    collated_page_results=$(awk -F/ '{print $3}' collated_page_results.tmp | sort -u)  # Retrieve domains from URLs, sort and remove duplicates
    rm collated_page_results.tmp  # Reset temp file for search results from each search term
    printf "%s" "$collated_page_results" > "data/search_term_${search_term:0:100}.tmp"  # Save search-term-specific results to temp file
    process_domains "$search_term" "$collated_page_results"  # Pass the search term and the results to the domain processing function
}

function process_domains {
    search_term="$1"
    pending_domains="$2"
    unfiltered_count=$(wc -w <<< "$pending_domains")  # Count number of unfilitered domains retrieved

    # Remove common subdomains
    while read -r subdomain; do  # Loop through common subdomains
        # Find domains with common subdomains, excluding 'www'
        domains_with_subdomains=$(grep "^${subdomain}\." <<< "$pending_domains" | grep -v "^www\.")
        # Log domains with common subdomains, excluding 'www'
        [[ -n "$domains_with_subdomains" ]] && log_event "$domains_with_subdomains" "subdomain"
        # Remove the subdomain, keeping only the root domain, sort and remove duplicates
        pending_domains=$(printf "%s" "$pending_domains" | sed "s/^${subdomain}\.//" | sort -u)
    done < "$subdomains_file"

    # Remove domains already in blocklist
    pending_domains=$(comm -23 <(printf "%s" "$pending_domains") "$raw_file")

    # Find blacklisted domains
    blacklisted_domains=$(comm -12 <(printf "%s" "$pending_domains") "$blacklist_file")
    log_event "$blacklisted_domains" "blacklist"

    # Remove whitelisted domains, excluding blacklisted domains
    whitelisted_domains=$(grep -Ff "$whitelist_file" <<< "$pending_domains" | grep -vxFf "$blacklist_file")
    whitelisted_count=$(wc -w <<< "$whitelisted_domains")  # Count number of whitelisted domains
    if [[ whitelisted_count -gt 0 ]]; then  # Check if whitelisted domains were found
        pending_domains=$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$whitelisted_domains"))
        log_event "$whitelisted_domains" "whitelist"
    fi
    
    # Remove domains that have whitelisted TLDs
    whiltelisted_tld_domains=$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' <<< "$pending_domains")
    whiltelisted_tld_count=$(wc -w <<< "$whiltelisted_tld_domains")  # Count number of domains with whitelisted TLDs
    if [[ whiltelisted_tld_count -gt 0 ]]; then  # Check if domains with whitelisted TLDs were found
        pending_domains=$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$whiltelisted_tld_domains"))
        log_event "$whiltelisted_tld_domains" "tld"
    fi

    # Remove IP addresses
    ip_addresses=$(grep -v '[a-z]' <<< "$pending_domains" | sort -u)
    if [[ -n "$ip_addresses" ]]; then
        pending_domains=$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$ip_addresses"))
        log_event "$ip_addresses" "ip_address"
        printf "%s\n" "$ip_addresses" >> ip_addresses.tmp  # Collate  IP addresses into temp file
    fi

    # Remove wildcard domains that are no longer in the blocklist
    comm -12 "$wildcards_file" "$raw_file" > "${wildcards_file}.tmp" && mv "${wildcards_file}.tmp" "$wildcards_file"
    redundant_domains_count=0  # Initialize redundant domains count
    # Remove redundant domains
    while read -r wildcard; do  # Loop through wildcard domains
        # Find redundant domains via wildcard matching
        redundant_domains=$(grep "\.${wildcard}$" <<< "$pending_domains")
        [[ -z "$redundant_domains" ]] && continue  # Skip to next wildcard if no matches found
        # Count number of redundant domains
        redundant_domains_count=$((redundant_domains_count + $(wc -w <<< "$redundant_domains")))
        pending_domains=$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$redundant_domains"))
        log_event "$redundant_domains" "redundant"
        log_event "$wildcard" "wildcard"
    done < "$wildcards_file"

    dead_domains_count=0  # Initialize dead domains count
    # Remove dead domains
    while read -r domain; do  # Loop through remaining pending domains
        [[ -z "$domains" ]] && continue  # Skip if domain is empty
        if ! host -t a "$domain" | grep -q 'has no A record'; then  # Check if the domain has an A record
            continue  # Skip to next domain if alive
        fi
        pending_domains="${pending_domains/${domain}/}"  # Remove dead domain
        ((dead_domains_count++))  # Increment dead domains count
        log_event "$domain" "dead"
        printf "%s\n" "$domain" >> "$dead_domains_file"
    done <<< "$pending_domains"
    format_list "$dead_domains_file"

    # Find matching domains in toplist, excluding blacklisted domains
    domains_in_toplist=$(comm -12 <(printf "%s" "$pending_domains") "$toplist_file" | grep -vxFf "$blacklist_file")
    in_toplist_count=$(wc -w <<< "$domains_in_toplist")  # Count number of domains found in toplist
    if [[ in_toplist_count -gt 0 ]]; then  # Check if domains were found in toplist
        printf "%s\n" "$domains_in_toplist" >> in_toplist.tmp  # Save domains found in toplist into temp file
        log_event "$domains_in_toplist" "toplist"
    fi

    total_whitelisted_count=$((whitelisted_count + whiltelisted_tld_count))  # Calculate sum of whitelisted domains
    final_count=$(wc -w <<< "$pending_domains")  # Count number of domains after filtering
    log_search_term "$search_term" "$unfiltered_count" "$final_count" "$total_whitelisted_count" "$dead_domains_count" "$redundant_domains_count" "$in_toplist_count" "$domains_in_toplist"
    printf "%s\n" "$pending_domains" >> filtered_domains.tmp  # Collate the filtered domains to a temp file
}

function merge_domains {
    sleep 0.5
    # Exit if no new domains to add or temp file is missing
    if [[ ! -s filtered_domains.tmp ]]; then
        printf "\nNo new domains to add.\n\n"
        exit
    fi

    format_list filtered_domains.tmp
    filtered_domains_count=$(wc -w < filtered_domains.tmp)  # Count number of filtered domains
    # Print domains if count is less than or equal to 10
    if [[ filtered_domains_count -le 10 ]]; then
        printf "\nNew domains retrieved (%s):\n" "$filtered_domains_count"
        sleep 0.5
        cat filtered_domains.tmp
    else
        printf "\nNew domains retrieved: %s\n" "$filtered_domains_count"
    fi
    sleep 0.5

    # Print out domains in toplist and IP addresses
    if [[ -f in_toplist.tmp ]] || [[ -f ip_addresses.tmp ]]; then
        printf "\nEntries requiring manual review:\n"
        sleep 0.5
    fi

    # Exit with error and without adding domains to the raw file if domains were found in the toplist
    if [[ -f in_toplist.tmp ]]; then
        format_list in_toplist.tmp
        awk 'NF {print $0 " (toplist)"}' in_toplist.tmp
        sleep 0.5
        printf "\nPending domains saved for rerun.\n\n"
        exit 1
    fi

    # If IP addresses were found, print out addresses
    if [[ -f ip_addresses.tmp ]]; then
        format_list ip_addresses.tmp
        awk 'NF {print $0 " (IP address)"}' ip_addresses.tmp
    fi

    count_before=$(wc -w < "$raw_file")
    cat filtered_domains.tmp >> "$raw_file"  # Add new domains to blocklist
    format_list "$raw_file"
    log_event "$(<filtered_domains.tmp)" new_domain
    count_after=$(wc -w < "$raw_file")
    count_difference=$((count_after - count_before))
    printf "\nAdded new domains to blocklist.\nBefore: %s  Added: %s  After: %s\n\n" "$count_before" "$count_difference" "$count_after"
    [[ -f ip_addresses.tmp ]] && exit 1  # Exit with error if IP addresses were found
}

function log_event {
    # Log domain processing events
   printf "%s" "$1" | awk -v event="$2" -v time="$time_format" '{print time "," event "," $0 ",new"}' >> "$domain_log"
}

function log_search_term {
    # Print and log statistics for search term
    search_term="\"${1:0:100}...\""  # Shorten to first 100 characters
    awk -v term="$search_term" -v raw="$2" -v final="$3" -v whitelist="$4" -v dead="$5" -v redundant="$6" -v toplist_count="$7" -v toplist_domains="$(printf "%s" "$8" | tr '\n' ' ')" -v time="$time_format" 'BEGIN {print time","term","raw","final","whitelist","dead","redundant","toplist_count","toplist_domains}' >> "$search_log"
    printf "%s\nRaw: %s  Final: %s  Whitelisted: %s  Dead: %s  Redundant: %s  Toplist: %s\n" "$search_term" "$2" "$3" "$4" "$5" "$6" "$7"
}

function format_list {
    [[ -f "$1" ]] || return  # Return if file does not exist
    # If file is a CSV file, do not sort
    if [[ "$1" == *.csv ]]; then
        sed -i 's/\r$//' "$1"  
        return
    fi
    # Format carriage return characters, remove empty lines, sort and remove duplicates
    tr -d '\r' < "$1" | sed '/^$/d' | sort -u > "${1}.tmp" && mv "${1}.tmp" "$1"
}

function cleanup {
    [[ -f filtered_domains.tmp ]] && rm filtered_domains.tmp  # Reset temp file for filtered domains
    [[ -f ip_addresses.tmp ]] && rm ip_addresses.tmp  # Reset temp file for IP addresses
    # Reset temp search results files if there are no domains found in toplist
    if [[ ! -f in_toplist.tmp ]] && ls data/search_term_*.tmp &> /dev/null; then
        rm data/search_term_*.tmp
    fi
    [[ -f in_toplist.tmp ]] && rm in_toplist.tmp  # Reset temp file for domains found in toplist
}

trap cleanup EXIT
main

#!/bin/bash
raw_file='data/raw.txt'
toplist_file='data/toplist.txt'
source_log='data/source_log.csv'
domain_log='data/domain_log.csv'
search_terms_file='config/search_terms.csv'
whitelist_file='config/whitelist.txt'
blacklist_file='config/blacklist.txt'
subdomains_file='data/subdomains.txt'
root_domains_file='data/root_domains.txt'
subdomains_to_remove_file='config/subdomains_to_remove.txt'
wildcards_file='data/wildcards.txt'
redundant_domains_file='data/redundant_domains.txt'
dead_domains_file='data/dead_domains.txt'
time_format="$(TZ=Asia/Singapore date +"%H:%M:%S %d-%m-%y")"

# grep '\..*\.' domains.txt | awk -F '.' '{print $2"."$3"."$4}' | sort | uniq -d  # Find root domains that occur more than once

# If running locally, use locally stored secrets instead of environment variables
if [[ "$CI" != true ]]; then
    google_search_id=
    google_search_api_key=
    aa419_api_id=
fi

function main {
    command -v csvstat &> /dev/null || pip install -q csvkit  # Install cvstat
    command -v jq &> /dev/null || apt-get install -yqq jq  # Install jq
    for file in config/* data/*; do  # Format files in the config and data directory
        format_list "$file"
    done
    # Remove wildcard domains that are no longer in the blocklist (needs to run before domain processing)
    comm -12 "$wildcards_file" "$raw_file" > wildcards.tmp && mv wildcards.tmp "$wildcards_file"

    # Retrieve domains from sources only if there are no existing domain files
    if ! ls data/domains_*.tmp &> /dev/null; then
        source_aa419
        source_guntab
        source_stopgunscams
        source_petscams
        source_scamdelivery
        source_scamdirectory
        source_google_search
        merge_domains
        exit
    fi

    printf "\nUsing existing list of retrieved domains.\n\n"
    for temp_domains_file in data/domains_*.tmp; do  # Loop through temp domains file
        case $temp_domains_file in
            *google_search*)
                source="Google Search"
                item=${temp_domains_file#data/domains_google_search_}  # Remove header from file name
                item=${item%.tmp}  # Rename extension from file name
                ;;
            *aa419*)
                source="aa419.org" 
                item="$source"
                ;;
            *guntab*)
                source="guntab.com" 
                item="$source"
                ;;
            *stopgunscams*)
                source="stopgunscams.com" 
                item="$source"
                ;;
            *petscams*)
                source="petscams.com" 
                item="$source"
                ;;
            *scamdelivery*)
                source="scam.delivery" 
                item="$source"
                ;;
            *scamdirectory*)
                source="scam.directory" 
                item="$source"
                ;;
        esac
        process_source "$source" "$item" "$temp_domains_file"
    done
    merge_domains
}

function source_aa419 {
    source='aa419.org'
    url='https://api.aa419.org/fakesites'
    printf "\nSource: %s\n\n" "$source"
    for pgno in {1..20}; do  # Loop through pages
        query_params="${pgno}/500?fromupd=2022-01-01&Status=active&fields=Domain,Status,DateAdded,Updated"
        page_results=$(curl -s -H "Auth-API-Id:${aa419_api_id}" "${url}/${query_params}")
        jq -e '.[].Domain' &> /dev/null <<< "$page_results" || break  # Break out of loop when there are no more results
        jq -r '.[].Domain' <<< "$page_results" >> data/domains_aa419.tmp  # Collate all pages of domains
    done
    # Skip domain processing if no domains retrieved
    if [[ ! -f data/domains_aa419.tmp ]]; then
        log_source "$source" "$source" "0" "0" "0" "0" "0" ""
        return
    fi
    process_source "$source" "$source" "data/domains_aa419.tmp"
}

function source_guntab {
    source='guntab.com'
    url='https://www.guntab.com/scam-websites/'
    printf "\nSource: %s\n\n" "$source"
    curl -s "$url" | grep -zoE '<table class="datatable-list table">.*</table>' |  # Isolate table section
        grep -aoE '[[:alnum:].-]+\.[[:alnum:]-]{2,}' > data/domains_guntab.tmp  # Retrieve domains
    # Skip domain processing if no domains retrieved
    if [[ ! -s data/domains_guntab.tmp ]]; then
        log_source "$source" "$source" "0" "0" "0" "0" "0" ""
        return
    fi
    process_source "$source" "$source" "data/domains_guntab.tmp"
}

function source_stopgunscams {
    source='stopgunscams.com'
    url='https://stopgunscams.com'
    printf "\nSource: %s\n\n" "$source"
    for page in {1..5}; do  # Loop through pages
        curl -s "${url}/?page=${page}" | grep -oE '<a href="/[[:alnum:].-]+-[[:alnum:]-]{2,}"><div class="ap-a-img -ic">' \
            >> collated_stopgunscams_results.tmp  # Collate all pages of results
    done
    # Skip domain processing if no domains retrieved
    if [[ ! -f collated_stopgunscams_results.tmp ]]; then
        log_source "$source" "$source" "0" "0" "0" "0" "0" ""
        return
    fi
    # Strip results to domains
    sed 's/^<a href="\///; s/"><div class="ap-a-img -ic">//;
        s/-/./g' collated_stopgunscams_results.tmp > data/domains_stopgunscams.tmp
    rm collated_stopgunscams_results.tmp
    process_source "$source" "$source" "data/domains_stopgunscams.tmp"
}

function source_petscams {
    source='petscams.com'
    printf "\nSource: %s\n\n" "$source"
    # Loop through the two categories
    categories=('puppy-scammer-list' 'pet-delivery-scam')
    for category in "${categories[@]}"; do
        url="https://petscams.com/category/${category}/"
        for page in {2..25}; do  # Loop through pages
            curl -s "$url" | grep -oE "<a href=\"https://petscams.com/${category}/[[:alnum:].-]+-[[:alnum:]-]{2,}/\"" \
                >> collated_petscams_results.tmp  # Collate all pages of results
            url="https://petscams.com/category/${category}/page/${page}/"  # Add '/page' after first run
        done
    done
    # Skip domain processing if no domains retrieved
    if [[ ! -f collated_petscams_results.tmp ]]; then
        log_source "$source" "$source" "0" "0" "0" "0" "0" ""
        return
    fi
    # Strip results to domains
    sed 's/<a href="https:\/\/petscams.com\/puppy-scammer-list\///; s/<a href="https:\/\/petscams.com\/pet-delivery-scam\///;
        s/\/"//; s/-/./g' collated_petscams_results.tmp > data/domains_petscams.tmp
    rm collated_petscams_results.tmp
    process_source "$source" "$source" "data/domains_petscams.tmp"
}

function source_scamdelivery {
    source='scam.delivery'
    printf "\nSource: %s\n\n" "$source"
    url='https://scam.delivery/category/review'
    for page in {2..5}; do  # Loop through pages 
        curl -s "$url" | grep -oE 'title="[[:alnum:].-]+\.[[:alnum:]-]{2,}"></a>' \
            >> collated_scamdelivery_results.tmp  # Collate all pages of results
        url="https://scam.delivery/category/review/page/${page}"  # Add '/page' after first run
    done
    # Skip domain processing if no domains retrieved
    if [[ ! -f collated_scamdelivery_results.tmp ]]; then
        log_source "$source" "$source" "0" "0" "0" "0" "0" ""
        return
    fi
    # Strip results to domains
    sed 's/title="//; s/"><\/a>//' collated_scamdelivery_results.tmp |
        tr '[:upper:]' '[:lower:]' > data/domains_scamdelivery.tmp
    rm collated_scamdelivery_results.tmp
    process_source "$source" "$source" "data/domains_scamdelivery.tmp"
}

function source_scamdirectory {
    source='scam.directory'
    url='https://scam.directory/category'
    printf "\nSource: %s\n\n" "$source"
    curl -s "$url" | grep -oE 'href="/[[:alnum:].-]+-[[:alnum:]-]{2,}" title' |
        sed 's/href="\///; s/" title//' > data/domains_scamdirectory.tmp  # Retrieve domains
    # Skip domain processing if no domains retrieved
    if [[ ! -f data/domains_scamdirectory.tmp ]]; then
        log_source "$source" "$source" "0" "0" "0" "0" "0" ""
        return
    fi
    process_source "$source" "$source" "data/domains_scamdirectory.tmp"
}

function source_google_search {
    source='Google Search'
    printf "\nSource: %s\n\n" "$source"
    csvgrep -c 2 -m 'y' -i "$search_terms_file" | csvcut -c 1 | csvformat -U 1 | tail +2 |  # Filter out unused search terms
        while read -r search_term; do  # Loop through search terms
            search_google "$search_term"  # Pass the search term to the search function
        done
}

function search_google {
    url='https://customsearch.googleapis.com/customsearch/v1'
    search_term="${1//\"/}"  # Remove quotes from search term before encoding
    encoded_search_term=$(printf "%s" "$search_term" | sed 's/[^[:alnum:]]/%20/g')  # Replace whitespaces and non-alphanumeric characters with '%20'
    for start in {1..100..10}; do  # Loop through each page of results (max of 100 results)
        query_params="cx=${google_search_id}&key=${google_search_api_key}&exactTerms=${encoded_search_term}&start=${start}&excludeTerms=scam&filter=0"
        page_results=$(curl -s "${url}?${query_params}")
        jq -e '.items' &> /dev/null <<< "$page_results" || break # Break out of loop when there are no more results 
        jq -r '.items[].link' <<< "$page_results" >> collated_search_results.tmp  # Collate all pages of results
    done
    # Skip to next search term if no results retrieved
    if [[ ! -f collated_search_results.tmp ]]; then
        log_source "Google Search" "$search_term" "0" "0" "0" "0" "0" ""
        return
    fi
    # Strip URLs to domains
    awk -F/ '{print $3}' collated_search_results.tmp > "data/domains_google_search_${search_term:0:100}.tmp"
    rm collated_search_results.tmp
    process_source "Google Search" "$search_term" "data/domains_google_search_${search_term:0:100}.tmp"
}

function process_source {
    source="$1"
    item="$2"
    format_list "$3"  # Format temp file for pending domains
    pending_domains=$(<"$3")  # Store pending domains in a variable
    unfiltered_count=$(wc -w <<< "$pending_domains")  # Count number of unfiltered domains pending
    [[ "$3" != data/domains_*.tmp ]] && rm "$3"

    # Remove common subdomains
    while read -r subdomain; do  # Loop through common subdomains
        domains_with_subdomains=$(grep "^${subdomain}\." <<< "$pending_domains")  # Find domains with common subdomains
        [[ -z "$domains_with_subdomains" ]] && continue  # Skip to next subdomain if no matches found
        # Keep only root domains
        pending_domains=$(printf "%s" "$pending_domains" | sed "s/^${subdomain}\.//" | sort -u)
        # Collate subdomains for dead check
        printf "%s\n" "$domains_with_subdomains" >> subdomains.tmp
        # Collate root domains to exlude from dead check
        printf "%s\n" "$domains_with_subdomains" | sed "s/^${subdomain}\.//" >> root_domains.tmp
        # Find and log domains with common subdomains exluding 'www.'
        domains_with_subdomains=$(grep -v "^www\." <<< "$domains_with_subdomains")
        [[ -n "$domains_with_subdomains" ]] && log_event "$domains_with_subdomains" "subdomain" "$source"
    done < "$subdomains_to_remove_file"
    format_list subdomains.tmp
    format_list root_domains.tmp

    # Remove domains already in blocklist
    pending_domains=$(comm -23 <(printf "%s" "$pending_domains") "$raw_file")

    # Remove known dead domains
    dead_domains=$(comm -12 <(printf "%s" "$pending_domains") "$dead_domains_file")
    pending_domains=$(comm -23 <(printf "%s" "$pending_domains") "$dead_domains_file")
    log_event "$dead_domains" "dead" "$source"

    # Find blacklisted domains
    blacklisted_domains=$(comm -12 <(printf "%s" "$pending_domains") "$blacklist_file")
    log_event "$blacklisted_domains" "blacklist" "$source"

    # Remove whitelisted domains, excluding blacklisted domains
    whitelisted_domains=$(grep -Ff "$whitelist_file" <<< "$pending_domains" | grep -vxFf "$blacklist_file")
    whitelisted_count=$(wc -w <<< "$whitelisted_domains")  # Count number of whitelisted domains
    if [[ whitelisted_count -gt 0 ]]; then  # Check if whitelisted domains were found
        pending_domains=$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$whitelisted_domains"))
        log_event "$whitelisted_domains" "whitelist" "$source"
    fi
    
    # Remove domains that have whitelisted TLDs
    whiltelisted_tld_domains=$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' <<< "$pending_domains")
    whiltelisted_tld_count=$(wc -w <<< "$whiltelisted_tld_domains")  # Count number of domains with whitelisted TLDs
    if [[ whiltelisted_tld_count -gt 0 ]]; then  # Check if domains with whitelisted TLDs were found
        pending_domains=$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$whiltelisted_tld_domains"))
        log_event "$whiltelisted_tld_domains" "tld" "$source"
    fi

    # Remove IP addresses
    ip_addresses=$(grep -v '[a-z]' <<< "$pending_domains")
    if [[ -n "$ip_addresses" ]]; then
        pending_domains=$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$ip_addresses"))
        log_event "$ip_addresses" "ip_address" "$source"
        printf "%s\n" "$ip_addresses" >> ip_addresses.tmp  # Collate IP addresses into temp file
    fi

    redundant_domains_count=0  # Initialize redundant domains count
    # Remove redundant domains
    while read -r wildcard; do  # Loop through wildcard domains
        redundant_domains=$(grep "\.${wildcard}$" <<< "$pending_domains")  # Find redundant domains via wildcard matching
        [[ -z "$redundant_domains" ]] && continue  # Skip to next wildcard if no matches found
        # Count number of redundant domains
        redundant_domains_count=$((redundant_domains_count + $(wc -w <<< "$redundant_domains")))
        # Remove redundant domains
        pending_domains=$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$redundant_domains"))
        # Collate redundant domains for dead check
        printf "%s\n" "$redundant_domains" >> redundant_domains.tmp
        log_event "$redundant_domains" "redundant" "$source"
    done < "$wildcards_file"
    format_list redundant_domains.tmp

    # Find matching domains in toplist, excluding blacklisted domains
    domains_in_toplist=$(comm -12 <(printf "%s" "$pending_domains") "$toplist_file" | grep -vxFf "$blacklist_file")
    in_toplist_count=$(wc -w <<< "$domains_in_toplist")  # Count number of domains found in toplist
    if [[ in_toplist_count -gt 0 ]]; then  # Check if domains were found in toplist
        printf "%s\n" "$domains_in_toplist" >> in_toplist.tmp  # Save domains found in toplist into temp file
        log_event "$domains_in_toplist" "toplist" "$source"
    fi

    total_whitelisted_count=$((whitelisted_count + whiltelisted_tld_count))  # Calculate sum of whitelisted domains
    filtered_count=$(wc -w <<< "$pending_domains")  # Count number of domains after filtering
    log_source "$source" "$item" "$unfiltered_count" "$filtered_count" "$total_whitelisted_count" "$redundant_domains_count" "$in_toplist_count" "$domains_in_toplist"
    printf "%s\n" "$pending_domains" >> filtered_domains.tmp # Collate the filtered domains to a temp file
}

function merge_domains {
    sleep 0.5
    format_list filtered_domains.tmp
    # Exit if no new domains to add or temp file is missing
    if [[ ! -s filtered_domains.tmp ]]; then
        printf "\nNo new domains to add.\n\n"
        exit
    fi

    filtered_domains_count=$(wc -w < filtered_domains.tmp)  # Count total number of filtered domains
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

    # If IP addresses were found, print out addresses
    if [[ -f ip_addresses.tmp ]]; then
        format_list ip_addresses.tmp
        awk 'NF {print $0 " (IP address)"}' ip_addresses.tmp
    fi

    # Exit with error and without adding domains to the raw file if domains were found in the toplist
    if [[ -f in_toplist.tmp ]]; then
        format_list in_toplist.tmp
        awk 'NF {print $0 " (toplist)"}' in_toplist.tmp
        sleep 0.5
        printf "\nPending domains saved for rerun.\n\n"
        exit 1
    fi

    # Add filtered redundant domains to the redundant domains file
    [[ -f redundant_domains.tmp ]] && comm -12 filtered_domains.tmp redundant_domains.tmp >> "$redundant_domains_file"
    if [[ -f root_domains.tmp ]]; then
        root_domains=$(comm -12 filtered_domains.tmp root_domains.tmp)  # Retrieve filtered root domains
        subdomains=$(grep -Ff <<< "$root_domains" subdomains.tmp)  # Retrieve filtered subdomains
        printf "%s\n" "$root_domains" >> "$root_domains_file"  # Add the filtered root domains to the root domains file
        printf "%s\n" "$subdomains" >> "$subdomains_file"  # Add the filtered subdomiains to the subdomains file
        format_list "$root_domains_file"
        format_list "$subdomains_file"
    fi


    count_before=$(wc -w < "$raw_file")
    cat filtered_domains.tmp >> "$raw_file"  # Add new domains to blocklist
    format_list "$raw_file"
    log_event "$(<filtered_domains.tmp)" "new_domain" "all_sources"
    count_after=$(wc -w < "$raw_file")
    count_difference=$((count_after - count_before))
    printf "\nAdded new domains to blocklist.\nBefore: %s  Added: %s  After: %s\n\n" "$count_before" "$count_difference" "$count_after"

    rows=$(csvgrep -c 1 -m "$time_format" "$source_log" | tail +2)  # Find rows in log for this run
    source=$(grep -vFf <(printf "%s" "$rows") "$source_log")  # Remove rows from log
    rows=$(printf "%s" "$rows" | sed 's/no/yes/')  # Replace 'no' with 'yes' to record the domains were saved to the raw file
    printf "%s\n%s\n" "$source" "$rows" > "$source_log"  # Add the edited rows back to the log

    [[ -f ip_addresses.tmp ]] && exit 1 || exit 0  # Exit with error if IP addresses were found
}

function log_event {
    # Log domain processing events
    printf "%s" "$1" | awk -v type="$2" -v source="$3" -v time="$time_format" '{print time "," type "," $0 "," source}' >> "$domain_log"
}

function log_source {
    # Print and log statistics for source used
    item="$2"
    [[ "$1" == 'Google Search' ]] && item="\"${item:0:100}...\""  # Shorten Google Search term to first 100 characters
    awk -v source="$1" -v item="$item" -v raw="$3" -v final="$4" -v whitelist="$5" -v redundant="$6" -v toplist_count="$7" -v toplist_domains="$(printf "%s" "$8" | tr '\n' ' ')" -v time="$time_format" 'BEGIN {print time","source","item","raw","final","whitelist","redundant","toplist_count","toplist_domains",no"}' >> "$source_log"
    printf "Item: %s\nRaw: %s  Final: %s  Whitelisted: %s  Redundant: %s  Toplist: %s\n" "$item" "$3" "$4" "$5" "$6" "$7"
    printf "%s\n" "---------------------------------------------------------------------"
}

function format_list {
    [[ -f "$1" ]] || return  # Return if file does not exist
    # If file is a CSV file, do not sort
    if [[ "$1" == *.csv ]]; then
        sed -i 's/\r$//' "$1"  
        return
    fi
    # Remove whitespaces, carriage return characters, empty lines, sort and remove duplicates
    tr -d ' \r' < "$1" | tr -s '\n' | sort -u > "${1}.tmp" && mv "${1}.tmp" "$1"
}

function cleanup {
    [[ -f filtered_domains.tmp ]] && rm filtered_domains.tmp
    [[ -f ip_addresses.tmp ]] && rm ip_addresses.tmp
    [[ -f redundant_domains.tmp ]] && rm redundant_domains.tmp
    [[ -f subdomains.tmp ]] && rm subdomains.tmp
    [[ -f root_domains.tmp ]] && rm root_domains.tmp
    # Reset temp search results files if there are no domains found in toplist
    if [[ ! -f in_toplist.tmp ]] && ls data/domains_*.tmp &> /dev/null; then
        rm data/domains_*.tmp
    fi
    [[ -f in_toplist.tmp ]] && rm in_toplist.tmp  # Reset temp file for domains found in toplist
}

trap cleanup EXIT
main

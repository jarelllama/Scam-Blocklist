#!/bin/bash
raw_file='data/raw.txt'
source_log='config/source_log.csv'
domain_log='config/domain_log.csv'
search_terms_file='config/search_terms.csv'
whitelist_file='config/whitelist.txt'
blacklist_file='config/blacklist.txt'
toplist_file='data/toplist.txt'
root_domains_file='data/root_domains.txt'
subdomains_file='data/subdomains.txt'
subdomains_to_remove_file='config/subdomains.txt'
wildcards_file='data/wildcards.txt'
dead_domains_file='data/dead_domains.txt'
time_format="$(date -u +"%H:%M:%S %d-%m-%y")"
user_agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3.1 Safari/605.1.1'
query_count=0  # Initialize query count (only increments for Google Search terms)

# grep '\..*\.' domains.txt | awk -F '.' '{print $2"."$3"."$4}' | sort | uniq -d  # Find root domains that occur more than once

# If running locally, use locally stored secrets instead of environment variables
if [[ "$CI" != true ]]; then
    google_search_id=
    google_search_api_key=
    aa419_api_id=
fi

function main {
    command -v csvgrep &> /dev/null || pip install -q csvkit  # Install cvstat
    command -v jq &> /dev/null || apt-get install -yqq jq  # Install jq
    for file in config/* data/*; do  # Format files in the config and data directory
        format_list "$file"
    done
    [[ -d data/pending ]] && retrieve_existing  # Use existing pending domains if pending directory present
    [[ ! -d data/pending ]] && retrieve_new
    merge_domains
}

function retrieve_new {
        mkdir data/pending  # Intialize pending directory
        #source_aa419
        source_chainabuse
        #source_dfpi
        #source_guntab
        #source_petscams
        #source_scamdelivery  # Has captchas
        #source_scamdirectory
        #source_scamadviser
        #source_stopgunscams
        #source_google_search
}

function retrieve_existing {
    printf "\nUsing existing list of retrieved domains.\n\n"
    for temp_domains_file in data/pending/domains_*.tmp; do  # Loop through temp domains file
        source="Empty"  # Reintialize source
        case "$temp_domains_file" in
            *google_search*)
                source="Google Search" ;;
            *aa419.org*)
                source="aa419.org" ;;
            *guntab.com*)
                source="guntab.com" ;;
            *stopgunscams.com*)
                source="stopgunscams.com" ;;
            *petscams.com*)
                source="petscams.com" ;;
            *scam.delivery*)
                source="scam.delivery" ;;
            *scam.directory*)
                source="scam.directory" ;;
            *scamadviser.com*)
                source="scamadviser.com" ;;
            *dfpi.ca.gov*)
                source="dfpi.ca.gov" ;;
        esac
        [[ "$source" != 'Google Search' ]] && process_source "$source" "$source" "$temp_domains_file"
    done
    # Process Google search terms last
    for temp_domains_file in data/pending/domains_google_search_*.tmp; do
        [[ ! -f "$temp_domains_file" ]] && break
        item=${temp_domains_file#data/pending/domains_google_search_}  # Remove header from file name
        item=${item%.tmp}  # Remove file extension from file name
        process_source "Google Search" "$item" "$temp_domains_file"
    done
}

function source_aa419 {
    source='aa419.org'
    domains_file="data/pending/domains_${source}.tmp"
    url='https://api.aa419.org/fakesites'
    printf "\nSource: %s\n\n" "$source"
    touch "$domains_file"  # Initialize domains file
    for pgno in {1..20}; do  # Loop through pages
        query_params="${pgno}/500?fromadd=$(date +'%Y')-01-01&Status=active&fields=Domain"
        page_results=$(curl -s -H "Auth-API-Id:${aa419_api_id}" "${url}/${query_params}")  # Trailing / breaks API call
        jq -e '.[].Domain' &> /dev/null <<< "$page_results" || break  # Break out of loop when there are no more results
        jq -r '.[].Domain' <<< "$page_results" >> "$domains_file"
    done
    process_source "$source" "$source" "$domains_file"
}

function source_guntab {
    source='guntab.com'
    domains_file="data/pending/domains_${source}.tmp"
    url='https://www.guntab.com/scam-websites'
    printf "\nSource: %s\n\n" "$source"
    curl -s "${url}/" | grep -zoE '<table class="datatable-list table">.*</table>' |  # Isolate table section
        grep -aoE '[[:alnum:].-]+\.[[:alnum:]-]{2,}' | sed '501,$d' > "$domains_file"  # Keep only newest 500 domains (note piping to head causes errors in Github's runner)
    process_source "$source" "$source" "$domains_file"
}

function source_stopgunscams {
    source='stopgunscams.com'
    domains_file="data/pending/domains_${source}.tmp"
    url='https://stopgunscams.com'
    printf "\nSource: %s\n\n" "$source"
    for page in {1..5}; do  # Loop through pages
        curl -s "${url}/?page=${page}/" | grep -oE '<h4 class="-ih"><a href="/[[:alnum:].-]+-[[:alnum:]-]{2,}' |
            sed 's/<h4 class="-ih"><a href="\///; s/-/./g' >> "$domains_file"
    done
    process_source "$source" "$source" "$domains_file"
}

function source_petscams {
    source='petscams.com'
    domains_file="data/pending/domains_${source}.tmp"
    printf "\nSource: %s\n\n" "$source"
    # Loop through the two categories
    categories=('puppy-scammer-list' 'pet-delivery-scam')
    for category in "${categories[@]}"; do
        url="https://petscams.com/category/${category}"
        for page in {2..21}; do  # Loop through 20 pages
            curl -s "${url}/" | grep -oE "<a href=\"https://petscams.com/${category}/[[:alnum:].-]+-[[:alnum:]-]{2,}/\" " |
                sed 's/<a href="https:\/\/petscams.com\/puppy-scammer-list\///;
                s/<a href="https:\/\/petscams.com\/pet-delivery-scam\///; s/-\?[0-9]\?\/" //; s/-/./g' >> "$domains_file"
            url="https://petscams.com/category/${category}/page/${page}"  # Add '/page' after first run
        done
    done
    process_source "$source" "$source" "$domains_file"
}

function source_scamdelivery {
    source='scam.delivery'
    domains_file="data/pending/domains_${source}.tmp"
    printf "\nSource: %s\n\n" "$source"
    url='https://scam.delivery/category/review'
    for page in {2..3}; do  # Loop through 2 pages
        # Use User Agent to reduce captcha blocking
        curl -sA "$user_agent" "${url}/" | grep -oE 'title="[[:alnum:].-]+\.[[:alnum:]-]{2,}"></a>' |
            sed 's/title="//; s/"><\/a>//' >> "$domains_file"
        url="https://scam.delivery/category/review/page/${page}"  # Add '/page' after first run
    done
    process_source "$source" "$source" "$domains_file"
}

function source_scamdirectory {
    source='scam.directory'
    domains_file="data/pending/domains_${source}.tmp"
    url='https://scam.directory/category'
    printf "\nSource: %s\n\n" "$source"
    curl -s "${url}/" | grep -oE 'href="/[[:alnum:].-]+-[[:alnum:]-]{2,}" title' |
        sed 's/href="\///; s/" //; s/-/./g; 501,$d' > "$domains_file"  # Keep only newest 500 domains (note piping to head causes errors in Github's runner)
    process_source "$source" "$source" "$domains_file"
}

function source_scamadviser {
    source='scamadviser.com'
    domains_file="data/pending/domains_${source}.tmp"
    printf "\nSource: %s\n\n" "$source"
    url='https://www.scamadviser.com/articles'
    for page in {1..20}; do  # Loop through pages
        curl -s "${url}?p=${page}" | grep -oE '<div class="articles">.*<div>Read more</div>' |  # Isolate articles. Note trailing / breaks curl
            grep -oE '[A-Z][[:alnum:].-]+\.[[:alnum:]-]{2,}' >> "$domains_file"
    done
    process_source "$source" "$source" "$domains_file"
}

function source_dfpi {
    source='dfpi.ca.gov'
    domains_file="data/pending/domains_${source}.tmp"
    url='https://dfpi.ca.gov/crypto-scams'
    printf "\nSource: %s\n\n" "$source"
    curl -s "${url}/" | grep -oE '<td class="column-5">(<a href=")?(https?://)?[[:alnum:].-]+\.[[:alnum:]-]{2,}' |
        sed 's/<td class="column-5">//; s/<a href="//' > "$domains_file"
    process_source "$source" "$source" "$domains_file"
}

function source_chainabuse {
    source='chainabuse.com'
    domains_file="data/pending/domains_${source}.tmp"
    url='https://www.chainabuse.com'
    printf "\nSource: %s\n\n" "$source"
    for page in {0..9}; do  # Loop through pages
        curl -s "${url}/reports?page=${page}sort=newest/" | grep -oE '"domain":"(https?://)?[[:alnum:].-]+\.[[:alnum:]-]{2,}' |
            sed 's/"domain":"//' >> "$domains_file"
    done
    process_source "$source" "$source" "$domains_file"
}

function source_google_search {
    source='Google Search'
    printf "\nSource: %s\n\n" "$source"
    csvgrep -c 2 -m 'y' -i "$search_terms_file" | csvcut -c 1 | csvformat -U 1 | tail -n +2 |  # Filter out unused search terms
        while read -r search_term; do  # Loop through search terms
            search_google "$search_term"  # Pass the search term to the search function
        done
}

function search_google {
    url='https://customsearch.googleapis.com/customsearch/v1'
    search_term="${1//\"/}"  # Remove quotes from search term before encoding
    domains_file="data/pending/domains_google_search_${search_term:0:100}.tmp"
    touch "$domains_file"  # Create domains file if not present
    query_count=0  # Reinitliaze query count for each search term
    encoded_search_term=$(printf "%s" "$search_term" | sed 's/[^[:alnum:]]/%20/g')  # Replace whitespaces and non-alphanumeric characters with '%20'
    for start in {1..100..10}; do  # Loop through each page of results
        ((query_count++))  # Track number of search queries used
        query_params="cx=${google_search_id}&key=${google_search_api_key}&exactTerms=${encoded_search_term}&start=${start}&excludeTerms=scam&filter=0"
        page_results=$(curl -s "${url}?${query_params}")
        jq -e '.items' &> /dev/null <<< "$page_results" || break # Break out of loop if the first page has no results
        page_domains=$(jq -r '.items[].link' <<< "$page_results" | awk -F/ '{print $3}')
        printf "%s\n" "$page_domains" >> "$domains_file"  # Collate domains from each page
        [[ $(wc -w <<< "$page_domains") -lt 10 ]] && break  # Break out of loop if no more pages are required
    done
    process_source "Google Search" "$search_term" "$domains_file"
}

function process_source {
    source="$1"
    item="$2"
    domains_file="$3"

    # Skip to next source/item if no results retrieved
    if ! grep -q '[[:alnum:]]' "$domains_file"; then
        log_source "$source" "$item" "0" "0" "0" "0" "0" "0" "" "$query_count"
        return
    fi

    # Remove https:// and convert to lowercase
    sed 's/https:\/\///; s/http:\/\///' "$domains_file" | tr '[:upper:]' '[:lower:]' > domains.tmp && mv domains.tmp "$domains_file"
    format_list "$domains_file"  # Format temp file for pending domains
    pending_domains=$(<"$3")  # Store pending domains in a variable
    unfiltered_count=$(wc -w <<< "$pending_domains")  # Count number of unfiltered domains pending

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
        # Find and log domains with common subdomains exluding 'www'
        domains_with_subdomains=$(grep -v '^www\.' <<< "$domains_with_subdomains")
        [[ -n "$domains_with_subdomains" ]] && log_event "$domains_with_subdomains" "subdomain" "$source"
    done < "$subdomains_to_remove_file"
    format_list subdomains.tmp
    format_list root_domains.tmp

    # Remove domains already in blocklist
    pending_domains=$(comm -23 <(printf "%s" "$pending_domains") "$raw_file")

    # Remove known dead domains
    dead_domains=$(comm -12 <(printf "%s" "$pending_domains") <(sort "$dead_domains_file"))
    dead_count=$(wc -w <<< "$dead_domains")
    if [[ "$dead_count" -gt 0 ]]; then
        pending_domains=$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$dead_domains"))
        #log_event "$dead_domains" "dead" "$source"  # Logs too many lines
    fi

    # Find blacklisted domains
    blacklisted_domains=$(comm -12 <(printf "%s" "$pending_domains") "$blacklist_file")
    [[ -n "$blacklisted_domains" ]] && log_event "$blacklisted_domains" "blacklist" "$source"

    # Remove whitelisted domains, excluding blacklisted domains
    whitelisted_domains=$(comm -23 <(grep -Ff "$whitelist_file" <<< "$pending_domains") "$blacklist_file")
    whitelisted_count=$(wc -w <<< "$whitelisted_domains")
    if [[ "$whitelisted_count" -gt 0 ]]; then
        pending_domains=$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$whitelisted_domains"))
        log_event "$whitelisted_domains" "whitelist" "$source"
    fi

    # Remove domains that have whitelisted TLDs
    whiltelisted_tld_domains=$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' <<< "$pending_domains")
    whiltelisted_tld_count=$(wc -w <<< "$whiltelisted_tld_domains")
    if [[ "$whiltelisted_tld_count" -gt 0 ]]; then
        pending_domains=$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$whiltelisted_tld_domains"))
        log_event "$whiltelisted_tld_domains" "tld" "$source"
    fi

    # Remove invalid entries including IP addresses This excludes punycode TLDs (.xn--*)
    invalid_entries=$(grep -vE '^[[:alnum:].-]+\.[[:alnum:]-]*[[:alpha:]][[:alnum:]-]{1,}$' <<< "$pending_domains")
    if [[ -n "$invalid_entries" ]]; then
        pending_domains=$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$invalid_entries"))
        log_event "$invalid_entries" "invalid" "$source"
        printf "%s\n" "$invalid_entries" >> invalid_entries.tmp  # Collate invalid entries into temp file
    fi

    # Remove redundant domains
    redundant_domains_count=0  # Initialize redundant domains count for each source
    while read -r wildcard; do  # Loop through wildcard domains
        redundant_domains=$(grep "\.${wildcard}$" <<< "$pending_domains")  # Find redundant domains via wildcard matching
        [[ -z "$redundant_domains" ]] && continue  # Skip to next wildcard if no matches found
        redundant_domains_count=$((redundant_domains_count + $(wc -w <<< "$redundant_domains")))
        pending_domains=$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$redundant_domains"))
        log_event "$redundant_domains" "redundant" "$source"
    done < "$wildcards_file"

    # Find matching domains in toplist, excluding blacklisted domains
    domains_in_toplist=$(comm -23 <(comm -12 <(printf "%s" "$pending_domains") "$toplist_file") "$blacklist_file")
    in_toplist_count=$(wc -w <<< "$domains_in_toplist")
    if [[ "$in_toplist_count" -gt 0 ]]; then
        printf "%s\n" "$domains_in_toplist" >> in_toplist.tmp  # Save domains found in toplist into temp file
        log_event "$domains_in_toplist" "toplist" "$source"
    fi

    total_whitelisted_count=$((whitelisted_count + whiltelisted_tld_count))  # Calculate sum of whitelisted domains
    filtered_count=$(wc -w <<< "$pending_domains")  # Count number of domains after filtering
    log_source "$source" "$item" "$unfiltered_count" "$filtered_count" "$total_whitelisted_count" "$dead_count" "$redundant_domains_count" "$in_toplist_count" "$domains_in_toplist" "$query_count"
    printf "%s\n" "$pending_domains" >> filtered_domains.tmp # Collate the filtered domains to a temp file
}

function merge_domains {
    # Exit if no new domains to add or temp file is missing
    if ! grep -q '[[:alnum:]]' filtered_domains.tmp; then  # -s does not seem to work well here
        printf "\nNo new domains to add.\n\n"
        exit
    fi

    format_list filtered_domains.tmp
    printf "\nNew domains retrieved: %s\n" "$(wc -w < filtered_domains.tmp)"

    # Print out domains in toplist and invalid entries
    if [[ -f in_toplist.tmp ]] || [[ -f invalid_entries.tmp ]]; then
        printf "\nEntries requiring manual review:\n"
    fi
    # Print invalid entries
    if [[ -f invalid_entries.tmp ]]; then
        format_list invalid_entries.tmp
        awk 'NF {print $0 " (invalid)"}' invalid_entries.tmp
    fi
    # If domains were found in toplist, exit with error and without saving domains to raw file
    if [[ -f in_toplist.tmp ]]; then
        format_list in_toplist.tmp
        awk 'NF {print $0 " (toplist)"}' in_toplist.tmp
        printf "\nPending domains saved for rerun.\n\n"
        exit 1
    fi
    # Collate unfiltered subdomains and root domains
    if [[ -f root_domains.tmp ]]; then
        root_domains=$(comm -12 filtered_domains.tmp root_domains.tmp)  # Retrieve unfiltered root domains
        printf "%s\n" "$root_domains" >> "$root_domains_file"  # Add unfiltered root domains to root domains file to exclude from dead check
        grep -Ff <(printf "%s" "$root_domains") subdomains.tmp >> "$subdomains_file"  # Retrieve and add unfiltered subdomains to subdomains file for dead check
        format_list "$root_domains_file"
        format_list "$subdomains_file"
    fi

    count_before=$(wc -w < "$raw_file")
    cat filtered_domains.tmp >> "$raw_file"  # Add new domains to blocklist
    format_list "$raw_file"
    log_event "$(<filtered_domains.tmp)" "new_domain" "retrieval"
    count_after=$(wc -w < "$raw_file")
    count_difference=$((count_after - count_before))
    printf "\nAdded new domains to blocklist.\nBefore: %s  Added: %s  After: %s\n\n" "$count_before" "$count_difference" "$count_after"

    # Mark the source as saved in the source log file
    rows=$(grep -F "$time_format" "$source_log")  # Find rows in log for this run
    source=$(grep -vF "$time_format" "$source_log")  # Remove rows from log
    rows=$(printf "%s" "$rows" | sed 's/,no/,yes/')  # Replace ',no' with ',yes' to record that the domains were saved into the raw file
    printf "%s\n%s\n" "$source" "$rows" > "$source_log"  # Add the edited rows back to the log

    [[ -f invalid_entries.tmp ]] && exit 1 || exit 0  # Exit with error if invalid entries were found
}

function log_event {
    # Log domain processing events
    printf "%s\n" "$1" | awk -v type="$2" -v source="$3" -v time="$time_format" '{print time "," type "," $0 "," source}' >> "$domain_log"
}

function log_source {
    # Print and log statistics for source used
    item="$2"
    [[ "$1" == 'Google Search' ]] && item="\"${item:0:100}...\""  # Shorten Google Search term to first 100 characters
    awk -v source="$1" -v item="$item" -v raw="$3" -v final="$4" -v whitelist="$5" -v dead="$6" -v redundant="$7" -v toplist_count="$8" -v toplist_domains="$(printf "%s" "$9" | tr '\n' ' ')" -v time="$time_format" -v queries="${10}" 'BEGIN {print time","source","item","raw","final","whitelist","dead","redundant","toplist_count","toplist_domains","queries",no"}' >> "$source_log"
    printf "Item: %s\nRaw: %s  Final: %s  Whitelisted: %s  Dead: %s  Redundant: %s  Toplist: %s\n" "$item" "$3" "$4" "$5" "$6" "$7" "$8"
    printf "%s\n" "---------------------------------------------------------------------"
}

function format_list {
    [[ -f "$1" ]] || return  # Return if file does not exist
    if [[ "$1" == *.csv ]]; then  # If file is a CSV file, do not sort
        sed -i 's/\r//; /^$/d' "$1"
        return
    elif [[ "$1" == *dead_domains* ]]; then  # Do not sort the dead domains file
        tr -d ' \r' < "$1" | tr -s '\n' | awk '!seen[$0]++' > "${1}.tmp" && mv "${1}.tmp" "$1"
        return
    fi
    # Remove whitespaces, carriage return characters, empty lines, sort and remove duplicates
    tr -d ' \r' < "$1" | tr -s '\n' | sort -u > "${1}.tmp" && mv "${1}.tmp" "$1"
}

function cleanup {
    [[ ! -f in_toplist.tmp ]] && rm -r data/pending  # Initialize pending file is no pending domains to be saved
    find . -maxdepth 1 -type f -name "*.tmp" -delete
}

trap cleanup EXIT
main

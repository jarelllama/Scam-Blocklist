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
time_format=$(date -u +"%H:%M:%S %d-%m-%y")
user_agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3.1 Safari/605.1.1'

# grep '\..*\.' raw.txt | awk -F '.' '{print $2"."$3"."$4}' | sort | uniq -d  # Find root domains that occur more than once

# If running locally, use locally stored secrets instead of environment variables
[[ "$CI" != true ]] && { google_search_id=; google_search_api_key=; aa419_api_id=; }

function main {
    command -v csvgrep &> /dev/null || pip install -q csvkit  # Install csvkit
    command -v jq &> /dev/null || apt-get install -yqq jq  # Install jq
    for file in config/* data/*; do  # Format files in the config and data directory
        format_list "$file"
    done
    [[ -d data/pending ]] && retrieve_existing  # Use existing pending domains if pending directory present
    [[ ! -d data/pending ]] && retrieve_new
    merge_domains
}

function retrieve_new {
        mkdir data/pending  # Initialize pending directory
        printf "\n"
        source_aa419
        source_dfpi
        source_guntab
        source_petscams
        source_scamdelivery  # Has captchas
        source_scamdirectory
        source_scamadviser
        source_stopgunscams
        source_google_search
}

function retrieve_existing {
    printf "\nUsing existing lists of retrieved domains.\n\n"
    for domains_file in data/pending/domains_*.tmp; do  # Loop through temp domains file
        case "$domains_file" in
            *google_search*)
                continue ;;  # Skip Google Search till the end
            *aa419.org*)
                source='aa419.org' ;;
            *guntab.com*)
                source='guntab.com' ;;
            *stopgunscams.com*)
                source='stopgunscams.com' ;;
            *petscams.com*)
                source='petscams.com' ;;
            *scam.delivery*)
                source='scam.delivery' ;;
            *scam.directory*)
                source='scam.directory' ;;
            *scamadviser.com*)
                source='scamadviser.com' ;;
            *dfpi.ca.gov*)
                source='dfpi.ca.gov' ;;
            *)
                source='Unknown' ;;
        esac
        process_source
    done
    # Process Google search terms
    for domains_file in data/pending/domains_google_search_*.tmp; do
        [[ ! -f "$domains_file" ]] && break  # Break loop if no Google search terms found
        source='Google Search'
        search_term=${domains_file#data/pending/domains_google_search_}  # Remove header from file name
        search_term=${search_term%.tmp}  # Remove file extension from file name
        process_source
    done
}

function source_aa419 {
    source='aa419.org'
    domains_file="data/pending/domains_${source}.tmp"
    url='https://api.aa419.org/fakesites'
    query_params="1/500?fromadd=$(date +'%Y')-01-01&Status=active&fields=Domain"
    curl -sH "Auth-API-Id:${aa419_api_id}" "${url}/${query_params}" | jq -r '.[].Domain' >> "$domains_file"  # Note trailing slash breaks API call
    process_source
}

function source_guntab {
    source='guntab.com'
    domains_file="data/pending/domains_${source}.tmp"
    url='https://www.guntab.com/scam-websites'
    curl -s "${url}/" | grep -zoE '<table class="datatable-list table">.*</table>' |
        grep -aoE '[[:alnum:].-]+\.[[:alnum:]-]{2,}$' > "$domains_file"  # Note results are not sorted by time added
    process_source
}

function source_stopgunscams {
    source='stopgunscams.com'
    domains_file="data/pending/domains_${source}.tmp"
    url='https://stopgunscams.com'
    for page in {1..5}; do  # Loop through pages
        curl -s "${url}/?page=${page}/" | grep -oE '<h4 class="-ih"><a href="/[[:alnum:].-]+-[[:alnum:]-]{2,}' |
            sed 's/<h4 class="-ih"><a href="\///; s/-/./g' >> "$domains_file"
    done
    process_source
}

function source_petscams {
    source='petscams.com'
    domains_file="data/pending/domains_${source}.tmp"
    url="https://petscams.com"
    for page in {2..21}; do  # Loop through 20 pages
        curl -s "${url}/" | grep -oE '<a href="https://petscams.com/[[:alpha:]-]+-[[:alpha:]-]+/[[:alnum:].-]+-[[:alnum:]-]{2,}/">' |
             sed 's/<a href="https:\/\/petscams.com\/[[:alpha:]-]\+\///;
                s/-\?[0-9]\?\/">//; s/-/./g' >> "$domains_file"
        url="https://petscams.com/page/${page}"  # Add '/page' after first run
    done
    process_source
}

function source_scamdelivery {
    source='scam.delivery'
    domains_file="data/pending/domains_${source}.tmp"
    url='https://scam.delivery/category/review'
    for page in {2..3}; do  # Loop through 2 pages
        # Use User Agent to reduce captcha blocking
        curl -sA "$user_agent" "${url}/" | grep -oE 'title="[[:alnum:].-]+\.[[:alnum:]-]{2,}"></a>' |
            sed 's/title="//; s/"><\/a>//' >> "$domains_file"
        url="https://scam.delivery/category/review/page/${page}"  # Add '/page' after first run
    done
    process_source
}

function source_scamdirectory {
    source='scam.directory'
    domains_file="data/pending/domains_${source}.tmp"
    url='https://scam.directory/category'
    curl -s "${url}/" | grep -oE 'href="/[[:alnum:].-]+-[[:alnum:]-]{2,}" title' |
        sed 's/href="\///; s/" title//; s/-/./g; 301,$d' > "$domains_file"  # Keep only newly added domains
    process_source
}

function source_scamadviser {
    source='scamadviser.com'
    domains_file="data/pending/domains_${source}.tmp"
    url='https://www.scamadviser.com/articles'
    for page in {1..20}; do  # Loop through pages
        curl -s "${url}?p=${page}" | grep -oE '<div class="articles">.*<div>Read more</div>' |  # Isolate articles. Note trailing slash breaks curl
            grep -oE '[A-Z][[:alnum:].-]+\.[[:alnum:]-]{2,}' >> "$domains_file"
    done
    process_source
}

function source_dfpi {
    source='dfpi.ca.gov'
    domains_file="data/pending/domains_${source}.tmp"
    url='https://dfpi.ca.gov/crypto-scams'
    curl -s "${url}/" | grep -oE '<td class="column-5">(<a href=")?(https?://)?[[:alnum:].-]+\.[[:alnum:]-]{2,}' |
        sed 's/<td class="column-5">//; s/<a href="//; 31,$d' > "$domains_file"  # Keep only newly added domains
    process_source
}

function source_google_search {
    source='Google Search'
    rate_limited=false  # Initialize whether API is rate limited
    while read -r search_term; do  # Loop through search terms
        # Break out of loop if rate limited
        [[ "$rate_limited" == true ]] && { printf "! Custom Search JSON API rate limited.\n"; break; }
        search_google "$search_term"  # Search using search term if not rate limited
    done < <(csvgrep -c 2 -m 'y' -i "$search_terms_file" | csvcut -c 1 | csvformat -U 1 | tail -n +2)
}

function search_google {
    url='https://customsearch.googleapis.com/customsearch/v1'
    query_count=0  # Initialize query count for each search term
    search_term="${1//\"/}"  # Remove quotes from search term before encoding
    domains_file="data/pending/domains_google_search_${search_term:0:100}.tmp"
    touch "$domains_file"  # Create domains file if not present
    encoded_search_term=$(printf "%s" "$search_term" | sed 's/[^[:alnum:]]/%20/g')  # Replace non-alphanumeric characters with '%20'
    for start in {1..100..10}; do  # Loop through each page of results
        query_params="cx=${google_search_id}&key=${google_search_api_key}&exactTerms=${encoded_search_term}&start=${start}&excludeTerms=scam&filter=0"
        page_results=$(curl -s "${url}?${query_params}")
        grep -qF 'rateLimitExceeded' <<< "$page_results" && { rate_limited=true; break; }  # Break out of loop if rate limited
        ((query_count++))
        jq -e '.items' &> /dev/null <<< "$page_results" || break  # Break out of loop if the first page has no results
        page_domains=$(jq -r '.items[].link' <<< "$page_results" | awk -F/ '{print $3}')
        printf "%s\n" "$page_domains" >> "$domains_file"  # Collate domains from each page
        [[ $(wc -w <<< "$page_domains") -lt 10 ]] && break  # Break out of loop if no more pages are required
    done
    process_source
}

function process_source {
    # Initialize variables
    unfiltered_count=0 && filtered_count=0 && total_whitelisted_count=0
    dead_count=0 && redundant_count=0 && toplist_count=0 && domains_in_toplist=''
    [[ -z "$query_count" ]] && query_count=0
    [[ -z "$rate_limited" ]] && rate_limited=false

    # Skip to next source if no results retrieved
    ! grep -q '[[:alnum:]]' "$domains_file" && { log_source; return; }

    # Remove https:// or http:// and convert to lowercase
    sed 's/https\?:\/\///' "$domains_file" | tr '[:upper:]' '[:lower:]' > domains.tmp && mv domains.tmp "$domains_file"
    format_list "$domains_file"
    unfiltered_count=$(wc -l < "$domains_file")  # Count number of unfiltered domains pending
    pending_domains=$(<"$domains_file")  # Store pending domains in a variable

    # Remove common subdomains
    while read -r subdomain; do  # Loop through common subdomains
        domains_with_subdomains=$(grep "^${subdomain}\." <<< "$pending_domains")  # Find domains with common subdomains
        [[ -z "$domains_with_subdomains" ]] && continue  # Skip to next subdomain if no matches found
        # Keep only root domains
        pending_domains=$(printf "%s" "$pending_domains" | sed "s/^${subdomain}\.//" | sort -u)
        # Collate subdomains for dead check
        printf "%s\n" "$domains_with_subdomains" >> subdomains.tmp
        # Collate root domains to exclude from dead check
        printf "%s\n" "$domains_with_subdomains" | sed "s/^${subdomain}\.//" >> root_domains.tmp
        # Find and log domains with common subdomains excluding 'www'
        domains_with_subdomains=$(grep -v '^www\.' <<< "$domains_with_subdomains")
        [[ -n "$domains_with_subdomains" ]] && log_event "$domains_with_subdomains" "subdomain"
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
        #log_event "$dead_domains" "dead"  # Logs too many lines
    fi

    # Log blacklisted domains
    blacklisted_domains=$(comm -12 <(printf "%s" "$pending_domains") "$blacklist_file")
    [[ -n "$blacklisted_domains" ]] && log_event "$blacklisted_domains" "blacklist"

    # Remove whitelisted domains, excluding blacklisted domains
    whitelisted_domains=$(comm -23 <(grep -Ff "$whitelist_file" <<< "$pending_domains") "$blacklist_file")
    whitelisted_count=$(wc -w <<< "$whitelisted_domains")
    if [[ "$whitelisted_count" -gt 0 ]]; then
        pending_domains=$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$whitelisted_domains"))
        log_event "$whitelisted_domains" "whitelist"
    fi

    # Remove domains that have whitelisted TLDs
    whitelisted_tld_domains=$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' <<< "$pending_domains")
    whitelisted_tld_count=$(wc -w <<< "$whitelisted_tld_domains")
    if [[ "$whitelisted_tld_count" -gt 0 ]]; then
        pending_domains=$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$whitelisted_tld_domains"))
        log_event "$whitelisted_tld_domains" "tld"
    fi

    # Remove invalid entries including IP addresses. This excludes punycode TLDs (.xn--*)
    invalid_entries=$(grep -vE '^[[:alnum:].-]+\.[[:alnum:]-]*[[:alpha:]][[:alnum:]-]{1,}$' <<< "$pending_domains")
    if [[ -n "$invalid_entries" ]]; then
        pending_domains=$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$invalid_entries"))
        log_event "$invalid_entries" "invalid"
        printf "%s\n" "$invalid_entries" >> invalid_entries.tmp  # Collate invalid entries
    fi

    # Remove redundant domains
    redundant_count=0  # Initialize redundant domains count for each source
    while read -r wildcard; do  # Loop through wildcards
        redundant_domains=$(grep "\.${wildcard}$" <<< "$pending_domains")  # Find redundant domains via wildcard matching
        [[ -z "$redundant_domains" ]] && continue  # Skip to next wildcard if no matches found
        redundant_count=$((redundant_count + $(wc -w <<< "$redundant_domains")))
        pending_domains=$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$redundant_domains"))
        log_event "$redundant_domains" "redundant"
    done < "$wildcards_file"

    # Find matching domains in toplist, excluding blacklisted domains
    domains_in_toplist=$(comm -23 <(comm -12 <(printf "%s" "$pending_domains") "$toplist_file") "$blacklist_file")
    toplist_count=$(wc -w <<< "$domains_in_toplist")
    if [[ "$toplist_count" -gt 0 ]]; then
        printf "%s\n" "$domains_in_toplist" >> in_toplist.tmp  # Collate domains found in toplist
        log_event "$domains_in_toplist" "toplist"
    fi

    total_whitelisted_count=$((whitelisted_count + whitelisted_tld_count))  # Calculate sum of whitelisted domains
    filtered_count=$(tr -s '\n' <<< "$pending_domains" | wc -w)  # Count number of domains after filtering
    printf "%s\n" "$pending_domains" >> filtered_domains.tmp  # Collate the filtered domains into a temp file
    log_source
}

function merge_domains {
    # Exit if no new domains to add (-s does not seem to work well here)
    ! grep -q '[[:alnum:]]' filtered_domains.tmp && { printf "\nNo new domains to add.\n"; exit 0; }

    format_list filtered_domains.tmp

    # Print domains in toplist and invalid entries
    [[ -f in_toplist.tmp ]] || [[ -f invalid_entries.tmp ]] && printf "\nEntries requiring manual review:\n"
    # Print invalid entries
    if [[ -f invalid_entries.tmp ]]; then
        format_list invalid_entries.tmp
        awk 'NF {print $0 " (invalid)"}' invalid_entries.tmp
    fi
    # If domains were found in toplist, exit with error without saving domains to raw file
    if [[ -f in_toplist.tmp ]]; then
        format_list in_toplist.tmp
        awk 'NF {print $0 " (toplist)"}' in_toplist.tmp
        printf "\nPending domains saved for rerun.\n\n"
        exit 1
    fi
    # Collate filtered subdomains and root domains
    if [[ -f root_domains.tmp ]]; then
        root_domains=$(comm -12 filtered_domains.tmp root_domains.tmp)  # Retrieve filtered root domains
        printf "%s\n" "$root_domains" >> "$root_domains_file"  # Add filtered root domains to root domains file to exclude from dead check
        grep -Ff <(printf "%s" "$root_domains") subdomains.tmp >> "$subdomains_file"  # Retrieve and add filtered subdomains to subdomains file for dead check
        format_list "$root_domains_file"
        format_list "$subdomains_file"
    fi

    count_before=$(wc -l < "$raw_file")
    cat filtered_domains.tmp >> "$raw_file"  # Add new domains to blocklist
    format_list "$raw_file"
    log_event "$(<filtered_domains.tmp)" "new_domain" "retrieval"
    count_after=$(wc -l < "$raw_file")
    count_difference=$((count_after - count_before))
    printf "\nAdded new domains to blocklist.\nBefore: %s  Added: %s  After: %s\n" "$count_before" "$count_difference" "$count_after"

    # Mark the source as saved in the source log file
    rows=$(grep -F "$time_format" "$source_log")  # Find rows in log for this run
    temp_source_log=$(grep -vF "$time_format" "$source_log")  # Remove rows from log
    rows=$(printf "%s" "$rows" | sed 's/,no/,yes/')  # Replace ',no' with ',yes' to record that the domains were saved into the raw file
    printf "%s\n%s\n" "$temp_source_log" "$rows" > "$source_log"  # Add the edited rows back to the log

    # Exit with error if invalid entries were found
    [[ -f invalid_entries.tmp ]] && { printf "\n"; exit 1; } || exit 0
}

function log_event {
    # Log domain events
    [[ -n "$3" ]] && source="$3"
    printf "%s\n" "$1" | awk -v type="$2" -v source="$source" -v time="$time_format" '{print time "," type "," $0 "," source}' >> "$domain_log"
}

function log_source {
    # Print and log statistics for source used
    [[ "$source" == 'Google Search' ]] && search_term="\"${search_term:0:100}...\"" || search_term=''
    awk -v source="$source" -v search_term="$search_term" -v raw="$unfiltered_count" -v final="$filtered_count" -v whitelist="$total_whitelisted_count" -v dead="$dead_count" -v redundant="$redundant_count" \
        -v toplist_count="$toplist_count" -v toplist_domains="$(printf "%s" "$domains_in_toplist" | tr '\n' ' ')" -v queries="$query_count" -v rate_limited="$rate_limited" -v time="$time_format" \
        'BEGIN {print time","source","search_term","raw","final","whitelist","dead","redundant","toplist_count","toplist_domains","queries","rate_limited",no"}' >> "$source_log"
    [[ "$source" == 'Google Search' ]] && source="$search_term"
    printf "Source: %s\nRaw:%4s  Final:%4s  Whitelisted:%4s  Dead:%4s  Toplist:%4s\n" "$source" "$unfiltered_count" "$filtered_count" "$total_whitelisted_count" "$dead_count" "$toplist_count"
    printf "%s\n" "------------------------------------------------------------------"
}

function format_list {
    bash data/tools.sh "format" "$1"
}

function cleanup {
    [[ ! -f in_toplist.tmp ]] && rm -r data/pending  # Initialize pending directory is no pending domains to be saved
    find . -maxdepth 1 -type f -name "*.tmp" -delete
}

trap cleanup EXIT
main

#!/bin/bash
#
# Retrieves domains from various sources and outputs a raw file that contains
# the cumulative domains from all sources over time.

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly SEARCH_TERMS='config/search_terms.csv'
readonly WHITELIST='config/whitelist.txt'
readonly BLACKLIST='config/blacklist.txt'
readonly TOPLIST='data/toplist.txt'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'
readonly WILDCARDS='data/wildcards.txt'
readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly SOURCE_LOG='config/source_log.csv'
readonly DOMAIN_LOG='config/domain_log.csv'
TIME_FORMAT="$(date -u +"%H:%M:%S %d-%m-%y")"
readonly TIME_FORMAT

main() {
    set_up
    source
    build
}

set_up() {
    command -v jq &> /dev/null || apt-get install -yqq jq  # Install jq

    # Format files in the config and data directory
    for file in config/* data/*; do
        format_file "$file"
    done
}

# Function 'source' calls on the respective functions for each source
# to retrieve results. The results are processed and the output is a cumulative
# filtered domains file containing all filtered domains from this run.
source() {
    # Check whether to use existing retrieved result
    if [[ -d data/pending ]]; then
        printf "\nUsing existing lists of retrieved results.\n"
        readonly USE_EXISTING=true
    fi

    mkdir -p data/pending
    source_manual
    source_aa419
    source_dfpi
    source_guntab
    source_petscams
    source_scamdirectory
    source_scamadviser
    source_stopgunscams
    source_google_search
}

source_google_search() {
    command -v csvgrep &> /dev/null || pip install -q csvkit  # Install csvkit
    local -r source='Google Search'
    local -r ignore_from_light=false
    local rate_limited=false
    local search_term
    local results_file

    if [[ "$USE_EXISTING" == true ]]; then
        # Use existing retrieved results
        # Loop through the results from each search term
        for results_file in data/pending/domains_google_search_*.tmp; do
            [[ ! -f "$results_file" ]] && return
            # Remove header from file name
            search_term=${results_file#data/pending/domains_google_search_}
            # Remove file extension from file name to get search term
            search_term=${search_term%.tmp}
            process_source
        done
        return
    fi

    # Retrieve new results
    while read -r search_term; do  # Loop through search terms
        # Stop loop if rate limited
        if [[ "$rate_limited" == true ]]; then
            printf "\n\e[1;31mBoth Google Search API keys are rate limited.\e[0m\n"
            return
        fi
        search_google "$search_term"
    done < <(csvgrep -c 2 -m 'y' -i "$SEARCH_TERMS" | csvcut -c 1 | csvformat -U 1 | tail -n +2)
}

search_google() {
    local -r url='https://customsearch.googleapis.com/customsearch/v1'
    local search_term="${1//\"/}"
    local -r encoded_search_term="$(printf "%s" "$search_term" | sed 's/[^[:alnum:]]/%20/g')"
    local -r results_file="data/pending/domains_google_search_${search_term:0:100}.tmp"
    local -i query_count=0
    touch "$results_file"  # Create results file to ensure proper logging

    for start in {1..100..10}; do  # Loop through each page of results
        local query_params="cx=${google_search_id}&key=${google_search_api_key}&exactTerms=${encoded_search_term}&start=${start}&excludeTerms=scam&filter=0"
        local page_results="$(curl -s "${url}?${query_params}")"

        # Use next API key if first key is rate limited
        if grep -qF 'rateLimitExceeded' <<< "$page_results"; then
            # Exit loop if second key is also rate limited
            [[ "$google_search_id" == "$google_search_id_2" ]] && { rate_limited=true; break; }
            printf "\n\e[1mGoogle Search rate limited. Switching API keys.\e[0m\n"
            google_search_api_key="$google_search_api_key_2" && google_search_id="$google_search_id_2"
            continue  # Continue to next page (current rate limited page is not repeated)
        fi

        ((query_count++))  # Increment query count
        jq -e '.items' &> /dev/null <<< "$page_results" || break  # Break if page has no results
        page_domains="$(jq -r '.items[].link' <<< "$page_results" | awk -F/ '{print $3}')"  # Collate domains from each page
        printf "%s\n" "$page_domains" >> "$results_file"
        [[ $(wc -w <<< "$page_domains") -lt 10 ]] && break  # Break if no more pages are required
    done
    process_source
}

process_source() {
    # Initialize variables
    unfiltered_count=0 && filtered_count=0 && total_whitelisted_count=0
    dead_count=0 && redundant_count=0 && toplist_count=0 && domains_in_toplist=''
    [[ -z "$query_count" ]] && query_count=0
    [[ -z "$rate_limited" ]] && rate_limited=false
    [[ -z "$ignore_from_light" ]] && ignore_from_light=false

    [[ ! -f "$results_file" ]] && return  # Return if results file does not exist
    ! grep -q '[[:alnum:]]' "$results_file" && { log_source; return; }  # Skip to next source if no results retrieved

    # Remove https: or http:, remove slashes  and convert to lowercase
    sed 's/https\?://; s/\///g' "$results_file" | tr '[:upper:]' '[:lower:]' > domains.tmp && mv domains.tmp "$results_file"
    format_file "$results_file"
    unfiltered_count="$(wc -l < "$results_file")"  # Count number of unfiltered domains pending
    pending_domains="$(<"$results_file")" && rm "$results_file" # Migrate results to a variable

    # Remove known dead domains (dead domains file contains subdomains and redundant domains)
    dead_domains="$(comm -12 <(printf "%s" "$pending_domains") <(sort "$DEAD_DOMAINS"))"
    dead_count="$(wc -w <<< "$dead_domains")"
    [[ "$dead_count" -gt 0 ]] && pending_domains="$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$dead_domains"))"
    # Logging removed as it inflated log size by too much

    # Remove common subdomains
    while read -r subdomain; do  # Loop through common subdomains
        domains_with_subdomains="$(grep "^${subdomain}\." <<< "$pending_domains")"  # Find domains with common subdomains
        [[ -z "$domains_with_subdomains" ]] && continue  # Skip to next subdomain if no matches found
        # Keep only root domains
        pending_domains="$(printf "%s" "$pending_domains" | sed "s/^${subdomain}\.//" | sort -u)"
        # Collate subdomains for dead check
        printf "%s\n" "$domains_with_subdomains" >> subdomains.tmp
        # Collate root domains to exclude from dead check
        printf "%s\n" "$domains_with_subdomains" | sed "s/^${subdomain}\.//" >> root_domains.tmp
        # Log domains with common subdomains excluding 'www' (too many of them)
        domains_with_subdomains="$(grep -v '^www\.' <<< "$domains_with_subdomains")"
        [[ -n "$domains_with_subdomains" ]] && log_event "$domains_with_subdomains" "subdomain"
    done < "$SUBDOMAINS_TO_REMOVE"
    format_file subdomains.tmp && format_file root_domains.tmp

    # Remove domains already in raw file
    pending_domains="$(comm -23 <(printf "%s" "$pending_domains") "$RAW")"

    # Remove known parked domains
    parked_domains="$(comm -12 <(printf "%s" "$pending_domains") <(sort "$PARKED_DOMAINS"))"
    parked_count="$(wc -w <<< "$parked_domains")"
    if [[ "$parked_count" -gt 0 ]]; then
        pending_domains="$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$parked_domains"))"
        log_event "$parked_domains" "parked"
    fi

    # Log blacklisted domains
    blacklisted_domains="$(comm -12 <(printf "%s" "$pending_domains") "$BLACKLIST")"
    [[ -n "$blacklisted_domains" ]] && log_event "$blacklisted_domains" "blacklist"

    # Remove whitelisted domains, excluding blacklisted domains
    whitelisted_domains="$(comm -23 <(grep -Ff "$WHITELIST" <<< "$pending_domains") "$BLACKLIST")"
    whitelisted_count="$(wc -w <<< "$whitelisted_domains")"
    if [[ "$whitelisted_count" -gt 0 ]]; then
        pending_domains="$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$whitelisted_domains"))"
        log_event "$whitelisted_domains" "whitelist"
    fi

    # Remove domains that have whitelisted TLDs
    whitelisted_tld_domains="$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' <<< "$pending_domains")"
    whitelisted_tld_count="$(wc -w <<< "$whitelisted_tld_domains")"
    if [[ "$whitelisted_tld_count" -gt 0 ]]; then
        pending_domains="$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$whitelisted_tld_domains"))"
        log_event "$whitelisted_tld_domains" "tld"
    fi

    # Remove invalid entries including IP addresses. Punycode TLDs (.xn--*) are allowed
    invalid_entries="$(grep -vE '^[[:alnum:].-]+\.[[:alnum:]-]*[a-z][[:alnum:]-]{1,}$' <<< "$pending_domains")"
    if [[ -n "$invalid_entries" ]]; then
        pending_domains="$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$invalid_entries"))"
        awk 'NF {print $0 " (\033[1;31minvalid\033[0m)"}' <<< "$invalid_entries" >> manual_review.tmp
        printf "%s\n" "$invalid_entries" >> "$results_file"  # Save invalid entries for rerun
        log_event "$invalid_entries" "invalid"
    fi

    # Remove redundant domains
    redundant_count=0  # Initialize redundant domains count for each source
    while read -r wildcard; do  # Loop through wildcards
        redundant_domains="$(grep "\.${wildcard}$" <<< "$pending_domains")"  # Find redundant domains via wildcard matching
        [[ -z "$redundant_domains" ]] && continue  # Skip to next wildcard if no matches found
        redundant_count="$((redundant_count + $(wc -w <<< "$redundant_domains")))"
        pending_domains="$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$redundant_domains"))"
        log_event "$redundant_domains" "redundant"
    done < "$WILDCARDS"

    # Remove domains in toplist, excluding blacklisted domains
    domains_in_toplist="$(comm -23 <(comm -12 <(printf "%s" "$pending_domains") "$TOPLIST") "$BLACKLIST")"
    toplist_count="$(wc -w <<< "$domains_in_toplist")"
    if [[ "$toplist_count" -gt 0 ]]; then
        pending_domains="$(comm -23 <(printf "%s" "$pending_domains") <(printf "%s" "$domains_in_toplist"))"
        awk 'NF {print $0 " (\033[1;31mtoplist\033[0m)"}' <<< "$domains_in_toplist" >> manual_review.tmp
        printf "%s\n" "$domains_in_toplist" >> "$results_file"  # Save domains in toplist for rerun
        log_event "$domains_in_toplist" "toplist"
    fi

    total_whitelisted_count="$((whitelisted_count + whitelisted_tld_count))"  # Calculate sum of whitelisted domains
    filtered_count="$(printf "%s" "$pending_domains" | sed '/^$/d' | wc -w)"  # Count number of domains after filtering
    printf "%s\n" "$pending_domains" >> retrieved_domains.tmp  # Collate filtered domains
    [[ "$ignore_from_light" != true ]] && printf "%s\n" "$pending_domains" >> retrieved_light_domains.tmp  # Collate filtered domains from light sources
    log_source
}

build() {
    # Exit if no new domains to add (-s does not seem to work well here)
    ! grep -q '[[:alnum:]]' retrieved_domains.tmp && { printf "\n\e[1mNo new domains to add.\e[0m\n"; exit 0; }
    format_file retrieved_domains.tmp && format_file "$RAW"

    # Print domains requiring manual review
    [[ -f manual_review.tmp ]] && { printf "\n\e[1mEntries requiring manual review:\e[0m\n"; cat manual_review.tmp; }

    # Collate filtered subdomains and root domains
    if [[ -f root_domains.tmp ]]; then
        root_domains="$(comm -12 retrieved_domains.tmp root_domains.tmp)"  # Retrieve filtered root domains
        printf "%s\n" "$root_domains" >> "$ROOT_DOMAINS"  # Collate filtered root domains to exclude from dead check
        grep -Ff <(printf "%s" "$root_domains") subdomains.tmp >> "$SUBDOMAINS"  # Collate filtered subdomains for dead check
        format_file "$ROOT_DOMAINS" && format_file "$SUBDOMAINS"
    fi

    count_before="$(wc -l < "$RAW")"
    cat retrieved_domains.tmp >> "$RAW"  # Add domains to raw file
    format_file "$RAW"
    log_event "$(<retrieved_domains.tmp)" "new_domain" "retrieval"
    count_after="$(wc -l < "$RAW")"
    printf "\nAdded new domains to blocklist.\nBefore: %s  Added: %s  After: %s\n" "$count_before" "$((count_after - count_before))" "$count_after"

    # Mark sources as saved in the source log file
    rows="$(sed 's/,no/,yes/' <(grep -F "$TIME_FORMAT" "$SOURCE_LOG"))"  # Record that the domains were saved into the raw file
    temp_SOURCE_LOG="$(grep -vF "$TIME_FORMAT" "$SOURCE_LOG")"  # Remove rows from log
    printf "%s\n%s\n" "$temp_SOURCE_LOG" "$rows" > "$SOURCE_LOG"  # Add the updated rows to the log

    # Build raw light file
    if grep -q '[[:alnum:]]' retrieved_light_domains.tmp; then
        cat retrieved_light_domains.tmp >> "$RAW_LIGHT"
        format_file "$RAW_LIGHT"
    fi

    [[ -f manual_review.tmp ]] && { printf "\n"; exit 1; } || exit 0  # Exit with error if domains need to be manually reviewed
}

log_event() {
    # Log domain events
    [[ -n "$3" ]] && source="$3"
    printf "%s\n" "$1" | awk -v type="$2" -v source="$source" -v time="$TIME_FORMAT" '{print time "," type "," $0 "," source}' >> "$DOMAIN_LOG"
}

log_source() {
    # Print and log statistics for source used
    [[ "$source" == 'Google Search' ]] && search_term="\"${search_term:0:100}...\"" || search_term=''
    awk -v source="$source" -v search_term="$search_term" -v raw="$unfiltered_count" -v final="$filtered_count" -v whitelist="$total_whitelisted_count" -v dead="$dead_count" -v redundant="$redundant_count" \
        -v parked="$parked_count" -v toplist_count="$toplist_count" -v toplist_domains="$(printf "%s" "$domains_in_toplist" | tr '\n' ' ')" -v queries="$query_count" -v rate_limited="$rate_limited" -v time="$TIME_FORMAT" \
        'BEGIN {print time","source","search_term","raw","final","whitelist","dead","redundant","parked","toplist_count","toplist_domains","queries","rate_limited",no"}' >> "$SOURCE_LOG"
    [[ "$source" == 'Google Search' ]] && item="$search_term" || item="$source"
    excluded_count="$((dead_count + redundant_count + parked_count))"
    printf "\n\e[1mSource:\e[0m %s\n" "$item"
    printf "Raw:%4s  Final:%4s  Whitelisted:%4s  Excluded:%4s  Toplist:%4s\n" "$unfiltered_count" "$filtered_count" "$total_whitelisted_count" "$excluded_count" "$toplist_count"
    printf "%s\n" "----------------------------------------------------------------------"
}

# Shell wrapper to standardize the format of a file.
# Takes the file path as an argument.
format_file() {
    bash functions/tools.sh format "$1"
}

cleanup() {
    find data/pending -type d -empty -delete  # Initialize pending directory is no pending domains to be saved
    find . -maxdepth 1 -type f -name "*.tmp" -delete
}

# Source functions usage:
# Inputs:
#   source: name of the source to be used in the console and logs.
#
#   ignore_from_light: if true, results from the source are not included in light version
#     of the blocklist.
#
#   results_file: file path to save retrieved results to be used in further processing.
#
#   if USE_EXISTING is true, the retrieval process should be skipped and an existing
#     retrieved results file should be used instead.

source_manual() {
    source='Manual'
    ignore_from_light=
    results_file='data/pending/domains_manual.tmp'

    # Return if file not found (source is the file itself)
    [[ ! -f data/pending/domains_manual.tmp ]] && return

    grep -oE '[[:alnum:].-]+\.[[:alnum:]-]{2,}' "$results_file" > domains.tmp
    mv domains.tmp "$results_file"

    process_source
}

source_aa419() {
    local source='aa419.org'
    ignore_from_light=
    results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    url='https://api.aa419.org/fakesites'
    query_params="1/500?fromadd=$(date +'%Y')-01-01&Status=active&fields=Domain"
    curl -sH "Auth-API-Id:${aa419_api_id}" "${url}/${query_params}" |
        jq -r '.[].Domain' >> "$results_file"  # Trailing slash breaks API call

    process_source
}

source_guntab() {
    local source='guntab.com'
    ignore_from_light=true
    results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    url='https://www.guntab.com/scam-websites'
    curl -s "${url}/" |
        grep -zoE '<table class="datatable-list table">.*</table>' |
        grep -aoE '[[:alnum:].-]+\.[[:alnum:]-]{2,}$' > "$results_file"
    # Note results are not sorted by time added

    process_source
}

source_petscams() {
    local source='petscams.com'
    ignore_from_light=
    results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    url="https://petscams.com"
    for page in {2..21}; do  # Loop through 20 pages
        curl -s "${url}/" |
            grep -oE '<a href="https://petscams.com/[[a-z]-]+-[[a-z]-]+/[[:alnum:].-]+-[[:alnum:]-]{2,}/">' |
            sed 's/<a href="https:\/\/petscams.com\/[[:alpha:]-]\+\///;
                s/-\?[0-9]\?\/">//; s/-/./g' >> "$results_file"
        url="https://petscams.com/page/${page}"  # Add '/page' after first run
    done

    process_source
}

source_scamdirectory() {
    local source='scam.directory'
    ignore_from_light=
    results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    url='https://scam.directory/category'
    curl -s "${url}/" |
        grep -oE 'href="/[[:alnum:].-]+-[[:alnum:]-]{2,}" title' |
        sed 's/href="\///; s/" title//; s/-/./g; 301,$d' > "$results_file"
        # Keep only first 300 results

    process_source
}

source_scamadviser() {
    local source='scamadviser.com'
    ignore_from_light=
    results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    url='https://www.scamadviser.com/articles'
    for page in {1..20}; do  # Loop through pages
        curl -s "${url}?p=${page}" |  # Trailing slash breaks curl
            grep -oE '<div class="articles">.*<div>Read more</div>'
            grep -oE '[A-Z][[:alnum:].-]+\.[[:alnum:]-]{2,}' >> "$results_file"
    done

    process_source
}

source_dfpi() {
    local source='dfpi.ca.gov'
    ignore_from_light=
    results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    url='https://dfpi.ca.gov/crypto-scams'
    curl -s "${url}/" |
        grep -oE '<td class="column-5">(<a href=")?(https?://)?[[:alnum:].-]+\.[[:alnum:]-]{2,}' |
        sed 's/<td class="column-5">//; s/<a href="//; 31,$d' > "$results_file"
        # Keep only first 30 results

    process_source
}

source_stopgunscams() {
    local source='stopgunscams.com'
    ignore_from_light=
    results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    url='https://stopgunscams.com'
    for page in {1..5}; do
        curl -s "${url}/?page=${page}/" |
            grep -oE '<h4 class="-ih"><a href="/[[:alnum:].-]+-[[:alnum:]-]{2,}' |
            sed 's/<h4 class="-ih"><a href="\///; s/-/./g' >> "$results_file"
    done

    process_source
}

# Declare secrets if the script is not running in a GitHub Workflow
if [[ "$CI" != true ]]; then
    google_search_id=
    google_search_api_key=
    aa419_api_id=
    google_search_id_2=
    google_search_api_key_2=
fi

trap cleanup EXIT
main

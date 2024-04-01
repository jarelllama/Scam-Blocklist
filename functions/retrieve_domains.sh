#!/bin/bash

# Retrieves domains from various sources, processes them and outputs
# a raw file that contains the cumulative domains from all sources over time.

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

# Environment variables
readonly AA419_API_ID
readonly GOOGLE_SEARCH_ID
readonly GOOGLE_SEARCH_API_KEY
readonly GOOGLE_SEARCH_ID_2
readonly GOOGLE_SEARCH_API_KEY_2

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

process_source() {
    [[ ! -f "$results_file" ]] && return

    # Skip to next source if no results retrieved
    # [[ -s ]] does not seem to work well here
    if ! grep -q '[a-z]' "$results_file"; then
        log_source
        return
    fi

    format_file "$results_file"

    # Remove https:, http: and slashes to get domains,
    # and migrate to a variable
    domains="$(sed 's/https\?://; s/\///g' "$results_file" | sort -u)"
    rm "$results_file"

    # Count number of unfiltered domains pending
    # Note wc -w is used here as wc -l for an empty variable seems to
    # always output 1
    unfiltered_count="$(wc -w <<< "$domains")"

    # Remove known dead domains (includes subdomains and redundant domains)
    dead_domains="$(comm -12 <(printf "%s" "$domains") <(sort "$DEAD_DOMAINS"))"
    dead_count="$(wc -w <<< "$dead_domains")"
    if (( "$dead_count" > 0 )); then
        domains="$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$dead_domains"))"
    fi
    # Logging removed as it inflated log size by too much

    # Remove common subdomains
    local domains_with_subdomains  # Declare local variable in case while loop does not run
    while read -r subdomain; do  # Loop through common subdomains
        # Find domains and skip to next subdomain if none found
        domains_with_subdomains="$(grep "^${subdomain}\." <<< "$domains")" \
            || continue

        # Keep only root domains
        domains="$(printf "%s" "$domains" | sed "s/^${subdomain}\.//" | sort -u)"

        # Collate subdomains for dead check
        printf "%s\n" "$domains_with_subdomains" >> subdomains.tmp
        # Collate root domains to exclude from dead check
        printf "%s\n" "$domains_with_subdomains" | sed "s/^${subdomain}\.//" >> root_domains.tmp

        # Log domains with common subdomains excluding 'www' (too many of them)
        domains_with_subdomains="$(grep -v '^www\.' <<< "$domains_with_subdomains")" \
            && log_event "$domains_with_subdomains" subdomain
    done < "$SUBDOMAINS_TO_REMOVE"
    format_file subdomains.tmp
    format_file root_domains.tmp

    # Remove domains already in raw file
    domains="$(comm -23 <(printf "%s" "$domains") "$RAW")"

    # Remove known parked domains
    parked_domains="$(comm -12 <(printf "%s" "$domains") <(sort "$PARKED_DOMAINS"))"
    parked_count="$(wc -w <<< "$parked_domains")"
    if (( "$parked_count" > 0 )); then
        domains="$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$parked_domains"))"
        log_event "$parked_domains" parked
    fi

    # Log blacklisted domains
    blacklisted_domains="$(comm -12 <(printf "%s" "$domains") "$BLACKLIST")"
    [[ -n "$blacklisted_domains" ]] && log_event "$blacklisted_domains" blacklist

    # Remove whitelisted domains, excluding blacklisted domains
    whitelisted_domains="$(comm -23 <(grep -Ff "$WHITELIST" <<< "$domains") "$BLACKLIST")"
    whitelisted_count="$(wc -w <<< "$whitelisted_domains")"
    if (( "$whitelisted_count" > 0 )); then
        domains="$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$whitelisted_domains"))"
        log_event "$whitelisted_domains" whitelist
    fi

    # Remove domains that have whitelisted TLDs
    whitelisted_tld_domains="$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' <<< "$domains")"
    whitelisted_tld_count="$(wc -w <<< "$whitelisted_tld_domains")"
    if (( "$whitelisted_tld_count" > 0 )); then
        domains="$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$whitelisted_tld_domains"))"
        log_event "$whitelisted_tld_domains" tld
    fi

    # Remove invalid entries and IP addresses. Punycode TLDs (.xn--*) are allowed
    invalid_entries="$(grep -vE '^[[:alnum:].-]+\.[[:alnum:]-]*[a-z][[:alnum:]-]{1,}$' <<< "$domains")"
    if [[ -n "$invalid_entries" ]]; then
        domains="$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$invalid_entries"))"
        awk '{print $0 " (\033[1;31minvalid\033[0m)"}' <<< "$invalid_entries" >> manual_review.tmp
        # Save invalid entries for rerun
        printf "%s\n" "$invalid_entries" >> "$results_file"
        log_event "$invalid_entries" invalid
    fi

    # Remove redundant domains
    local redundant_domains  # Declare local variable in case while loop does not run
    local redundant_count=0
    while read -r wildcard; do  # Loop through wildcards
        # Find redundant domains via wildcard matching and skip to
        # next wildcard if none found
        redundant_domains="$(grep "\.${wildcard}$" <<< "$domains")" \
            || continue

        # Count number of redundant domains
        redundant_count="$((redundant_count + $(wc -w <<< "$redundant_domains")))"

        # Remove redundant domains
        domains="$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$redundant_domains"))"

        log_event "$redundant_domains" redundant
    done < "$WILDCARDS"

    # Remove domains in toplist, excluding blacklisted domains
    domains_in_toplist="$(comm -23 <(comm -12 <(printf "%s" "$domains") "$TOPLIST") "$BLACKLIST")"
    toplist_count="$(wc -w <<< "$domains_in_toplist")"
    if (( "$toplist_count" > 0 )); then
        domains="$(comm -23 <(printf "%s" "$domains") <(printf "%s" "$domains_in_toplist"))"
        awk '{print $0 " (\033[1;31mtoplist\033[0m)"}' <<< "$domains_in_toplist" >> manual_review.tmp
        # Save invalid entries for rerun
        printf "%s\n" "$domains_in_toplist" >> "$results_file"
        log_event "$domains_in_toplist" "toplist"
    fi

    # Collate filtered domains
    printf "%s\n" "$domains" >> retrieved_domains.tmp

    # Collate filtered domains from light sources
    if [[ "$ignore_from_light" != true ]]; then
        printf "%s\n" "$domains" >> retrieved_light_domains.tmp
    fi

    filtered_count="$(printf "%s" "$domains" | sed '/^$/d' | wc -w)"
    log_source
}

build() {
    # Exit if no new domains to add
    if ! grep -q '[a-z]' retrieved_domains.tmp; then
        printf "\n\e[1mNo new domains to add.\e[0m\n"
        exit 0
    fi

    format_file retrieved_domains.tmp

    # Print domains requiring manual review
    if [[ -f manual_review.tmp ]]; then
        printf "\n\e[1mEntries requiring manual review:\e[0m\n"
        cat manual_review.tmp
    fi

    # Collate filtered subdomains and root domains
    if [[ -f root_domains.tmp ]]; then
        # Find root domains (subdomains stripped off) in the filtered domains
        root_domains="$(comm -12 retrieved_domains.tmp root_domains.tmp)"

        # Collate filtered root domains to exclude from dead check
        printf "%s\n" "$root_domains" >> "$ROOT_DOMAINS"
        # Collate filtered subdomains for dead check
        grep -Ff <(printf "%s" "$root_domains") subdomains.tmp >> "$SUBDOMAINS"

        format_file "$ROOT_DOMAINS"
        format_file "$SUBDOMAINS"
    fi

    count_before="$(wc -l < "$RAW")"

    # Add domains to raw file and raw light file
    cat retrieved_domains.tmp >> "$RAW"
    cat retrieved_light_domains.tmp >> "$RAW_LIGHT"
    format_file "$RAW"
    format_file "$RAW_LIGHT"

    log_event "$(<retrieved_domains.tmp)" new_domain retrieval

    count_after="$(wc -l < "$RAW")"
    printf "\nAdded new domains to blocklist.\nBefore: %s  Added: %s  After: %s\n" \
        "$count_before" "$(( count_after - count_before ))" "$count_after"

    # Mark sources as saved in the source log file
    rows="$(sed 's/,no/,yes/' <(grep -F "$TIME_FORMAT" "$SOURCE_LOG"))"
    # Remove previous logs
    temp_source_log="$(grep -vF "$TIME_FORMAT" "$SOURCE_LOG")"
    # Add updated logs
    printf "%s\n%s\n" "$temp_source_log" "$rows" > "$SOURCE_LOG"

    # Exit with error if domains need to be manually reviewed
    if [[ -f manual_review.tmp ]]; then
        printf "\n"
        exit 1
    fi
}

# Function 'log_event' logs domain processing events into the domain log.
# $1: domains to log stored in a variable
# $2: event type (dead, whitelisted, etc.)
# $3: source
log_event() {
    [[ -n "$3" ]] && local source="$3"
    printf "%s\n" "$1" | awk -v type="$2" -v source="$source" -v time="$TIME_FORMAT" \
        '{print time "," type "," $0 "," source}' >> "$DOMAIN_LOG"
}

# Function 'log_source' prints and logs statistics for each source.
# The variables should be declared before running this function,
# otherwise, the default values are used.
log_source() {
    local item
    total_whitelisted_count="$(( whitelisted_count + whitelisted_tld_count ))"
    excluded_count="$(( dead_count + redundant_count + parked_count ))"

    if [[ "$source" == 'Google Search' ]]; then
        search_term="\"${search_term:0:100}...\""
        item="$search_term"
    fi

    echo "${TIME_FORMAT},${source},${search_term},${unfiltered_count:-0},
${filtered_count:-0},${total_whitelisted_count},${dead_count:-0},${redundant_count},
${parked_count:-0},${toplist_count:-0},$(tr '\n' ' ' <<< "$domains_in_toplist"),
${query_count:-0},${rate_limited:-false}" >> "$SOURCE_LOG"

    printf "\n\e[1mSource:\e[0m %s\n" "${item:-$source}"
    printf "Raw:%4s  Final:%4s  Whitelisted:%4s  Excluded:%4s  Toplist:%4s\n" \
        "${unfiltered_count:-0}" "${filtered_count:-0}" \
        "$total_whitelisted_count" "$excluded_count" "${toplist_count:-0}"
    printf "%s\n" "----------------------------------------------------------------------"
}

# Function 'format_file' calls a shell wrapper to
# standardize the format of a file.
# $1: file to format
format_file() {
    bash functions/tools.sh format "$1"
}

cleanup() {
    # Initialize pending directory if no pending domains to be saved
    find data/pending -type d -empty -delete

    find . -maxdepth 1 -type f -name '*.tmp' -delete
}

# Source functions are to retrieve results from the respective sources.
# Input:
#   $source: name of the source which is used in the console and logs
#   $ignore_from_light: if true, the results from the source are not included
#       in the light version (default is false)
#   $results_file: file path to save retrieved results to be used for
#       further processing
#   $USE_EXISTING: if true, skip the retrieval process and use the
#       existing results files
# Output:
#   $results_file (if results retrieved)

source_google_search() {
    # Install csvkit
    command -v csvgrep &> /dev/null || pip install -q csvkit

    local source='Google Search'
    local results_file
    local search_term

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

    local rate_limited=false
    local url='https://customsearch.googleapis.com/customsearch/v1'
    local search_id="$GOOGLE_SEARCH_ID"
    local search_api_key="$GOOGLE_SEARCH_API_KEY"

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
    local search_term="${1//\"/}"  # Remove quotes before encoding
    local encoded_search_term
    encoded_search_term="$(printf "%s" "$search_term" | sed 's/[^[:alnum:]]/%20/g')"
    local results_file="data/pending/domains_google_search_${search_term:0:100}.tmp"
    local query_params
    local page_results
    local page_domains
    local query_count=0

    touch "$results_file"  # Create results file to ensure proper logging

    for start in {1..100..10}; do  # Loop through each page of results
        query_params="cx=${search_id}&key=${search_api_key}&exactTerms=${encoded_search_term}&start=${start}&excludeTerms=scam&filter=0"
        page_results="$(curl -s "${url}?${query_params}")"

        # Use next API key if first key is rate limited
        if grep -qF 'rateLimitExceeded' <<< "$page_results"; then
            # Stop all searches if second key is also rate limited
            if [[ "$search_id" == "$GOOGLE_SEARCH_ID_2" ]]; then
                local -r rate_limited=true
                break
            fi

            printf "\n\e[1mGoogle Search rate limited. Switching API keys.\e[0m\n"

            # Switch API keys
            readonly search_api_key="$GOOGLE_SEARCH_API_KEY_2"
            readonly search_id="$GOOGLE_SEARCH_ID_2"

            # Continue to next page (current rate limited page is not repeated)
            continue
        fi

        (( query_count++ ))

        # Stop search term if page has no results
        jq -e '.items' &> /dev/null <<< "$page_results" || break

        # Get domains from each page
        page_domains="$(jq -r '.items[].link' <<< "$page_results" | awk -F/ '{print $3}')"
        printf "%s\n" "$page_domains" >> "$results_file"

        # Stop search term if no more pages are required
        (( $(wc -w <<< "$page_domains") < 10 )) && break
    done

    process_source
}

source_manual() {
    local source='Manual'
    local results_file='data/pending/domains_manual.tmp'

    # Return if results file not found (source is the file itself)
    [[ ! -f "$results_file" ]] && return

    grep -oE '[[:alnum:].-]+\.[[:alnum:]-]{2,}' "$results_file" > domains.tmp
    mv domains.tmp "$results_file"

    process_source
}

source_aa419() {
    local source='aa419.org'
    local results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://api.aa419.org/fakesites'
    local query_params
    query_params="1/500?fromadd=$(date +'%Y')-01-01&Status=active&fields=Domain"
    curl -sH "Auth-API-Id:${AA419_API_ID}" "${url}/${query_params}" |
        jq -r '.[].Domain' >> "$results_file"  # Trailing slash breaks API call

    process_source
}

source_guntab() {
    local source='guntab.com'
    local ignore_from_light=true
    local results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://www.guntab.com/scam-websites'
    curl -s "${url}/" |
        grep -zoE '<table class="datatable-list table">.*</table>' |
        grep -aoE '[[:alnum:].-]+\.[[:alnum:]-]{2,}$' > "$results_file"
    # Note results are not sorted by time added

    process_source
}

source_petscams() {
    local source='petscams.com'
    local results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url="https://petscams.com"
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
    local results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://scam.directory/category'
    curl -s "${url}/" |
        grep -oE 'href="/[[:alnum:].-]+-[[:alnum:]-]{2,}" title' |
        sed 's/href="\///; s/" title//; s/-/./g; 301,$d' > "$results_file"
        # Keep only first 300 results

    process_source
}

source_scamadviser() {
    local source='scamadviser.com'
    local results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://www.scamadviser.com/articles'
    for page in {1..20}; do  # Loop through pages
        curl -s "${url}?p=${page}" |  # Trailing slash breaks curl
            grep -oE '<div class="articles">.*<div>Read more</div>'
            grep -oE '[A-Z][[:alnum:].-]+\.[[:alnum:]-]{2,}' >> "$results_file"
    done

    process_source
}

source_dfpi() {
    local source='dfpi.ca.gov'
    local results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://dfpi.ca.gov/crypto-scams'
    curl -s "${url}/" |
        grep -oE '<td class="column-5">(<a href=")?(https?://)?[[:alnum:].-]+\.[[:alnum:]-]{2,}' |
        sed 's/<td class="column-5">//; s/<a href="//; 31,$d' > "$results_file"
        # Keep only first 30 results

    process_source
}

source_stopgunscams() {
    local source='stopgunscams.com'
    local results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://stopgunscams.com'
    for page in {1..5}; do
        curl -s "${url}/?page=${page}/" |
            grep -oE '<h4 class="-ih"><a href="/[[:alnum:].-]+-[[:alnum:]-]{2,}' |
            sed 's/<h4 class="-ih"><a href="\///; s/-/./g' >> "$results_file"
    done

    process_source
}

trap cleanup EXIT

command -v jq &> /dev/null || apt-get install -yqq jq

for file in config/* data/*; do
    format_file "$file"
done

source

build

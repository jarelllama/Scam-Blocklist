#!/bin/bash

# Retrieves domains from various sources, processes them and outputs
# a raw file that contains the cumulative domains from all sources over time.

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly SEARCH_TERMS='config/search_terms.csv'
readonly WHITELIST='config/whitelist.txt'
readonly BLACKLIST='config/blacklist.txt'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'
readonly WILDCARDS='data/wildcards.txt'
readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly PHISHING_TARGETS='config/phishing_targets.csv'
readonly SOURCE_LOG='config/source_log.csv'
readonly DOMAIN_LOG='config/domain_log.csv'
TIME_FORMAT="$(date -u +"%H:%M:%S %d-%m-%y")"

# Function 'source' calls on the respective functions for each source to
# retrieve results. The results are then passed to the 'process_source'
# function for further processing.
source() {
    # Check whether to use existing retrieved results
    if [[ -d data/pending ]]; then
        printf "\nUsing existing lists of retrieved results.\n"
        readonly USE_EXISTING=true
    fi

    mkdir -p data/pending

    source_manual
    source_aa419
    #source_dfpi  # Deactivated
    #source_dnstwist  #TODO
    source_guntab
    source_petscams
    source_scamdirectory
    source_scamadviser
    source_stopgunscams
    source_google_search
}

# Function 'process_source' filters results retrieved from a source.
# The output is a cumulative filtered domains file containing all filtered
# domains from all sources in this run.
process_source() {
    [[ ! -f "$results_file" ]] && return

    format_file "$results_file"

    # Remove http(s): and slashes to get domains. Then migrate to a variable
    # (some of the results are in URL form so this is done here once instead of
    # multiple times in the source functions)
    domains="$(sed 's/https\?://; s/\///g' "$results_file" | sort -u)"
    rm "$results_file"

    # Count number of unfiltered domains pending
    # Note wc -w is used here as wc -l for an empty variable seems to
    # always output 1.
    raw_count="$(wc -w <<< "$domains")"

    # Remove known dead domains (includes subdomains and redundant domains)
    dead_domains="$(comm -12 <(echo "$domains") <(sort "$DEAD_DOMAINS"))"
    dead_count="$(wc -w <<< "$dead_domains")"
    domains="$(comm -23 <(echo "$domains") <(echo "$dead_domains"))"
    # Logging removed as it inflated log size

    # Remove common subdomains
    local domains_with_subdomains  # Declare local variable in case while loop does not run
    while read -r subdomain; do  # Loop through common subdomains
        # Find domains with subdomains and skip to next subdomain if none found
        domains_with_subdomains="$(grep "^${subdomain}\." <<< "$domains")" \
            || continue

        # Keep only root domains
        domains="$(echo "$domains" | sed "s/^${subdomain}\.//" | sort -u)"

        # Collate subdomains for dead check
        printf "%s\n" "$domains_with_subdomains" >> subdomains.tmp
        # Collate root domains to exclude from dead check
        printf "%s\n" "$domains_with_subdomains" | sed "s/^${subdomain}\.//" >> root_domains.tmp

        # Log domains with common subdomains excluding 'www' (too many of them)
        log_event "$(grep -v '^www\.' <<< "$domains_with_subdomains")" subdomain
    done < "$SUBDOMAINS_TO_REMOVE"
    format_file subdomains.tmp
    format_file root_domains.tmp

    # Remove domains already in raw file
    domains="$(comm -23 <(echo "$domains") "$RAW")"

    # Remove known parked domains
    parked_domains="$(comm -12 <(echo "$domains") <(sort "$PARKED_DOMAINS"))"
    parked_count="$(wc -w <<< "$parked_domains")"
    domains="$(comm -23 <(echo "$domains") <(echo "$parked_domains"))"
    # Logging removed as it inflated log size

    # Log blacklisted domains
    log_event "$(comm -12 <(echo "$domains") "$BLACKLIST")" blacklist

    # Remove whitelisted domains, excluding blacklisted domains
    whitelisted_domains="$(comm -23 <(grep -Ff "$WHITELIST" <<< "$domains") "$BLACKLIST")"
    whitelisted_count="$(wc -w <<< "$whitelisted_domains")"
    domains="$(comm -23 <(echo "$domains") <(echo "$whitelisted_domains"))"
    log_event "$whitelisted_domains" whitelist

    # Remove domains that have whitelisted TLDs
    whitelisted_tld_domains="$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' <<< "$domains")"
    whitelisted_tld_count="$(wc -w <<< "$whitelisted_tld_domains")"
    domains="$(comm -23 <(echo "$domains") <(echo "$whitelisted_tld_domains"))"
    log_event "$whitelisted_tld_domains" tld

    # Remove invalid entries and IP addresses. Punycode TLDs (.xn--*) are allowed
    invalid_entries="$(grep -vE '^[[:alnum:].-]+\.[[:alnum:]-]*[a-z][[:alnum:]-]{1,}$' <<< "$domains")"
    if [[ -n "$invalid_entries" ]]; then
        domains="$(comm -23 <(echo "$domains") <(echo "$invalid_entries"))"
        awk '{print $0 " (invalid)"}' <<< "$invalid_entries" >> manual_review.tmp
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
        domains="$(comm -23 <(echo "$domains") <(echo "$redundant_domains"))"

        log_event "$redundant_domains" redundant
    done < "$WILDCARDS"

    # Remove domains in toplist, excluding blacklisted domains
    download_toplist
    domains_in_toplist="$(comm -23 <(comm -12 <(echo "$domains") toplist.tmp) "$BLACKLIST")"
    toplist_count="$(wc -w <<< "$domains_in_toplist")"
    if (( "$toplist_count" > 0 )); then
        domains="$(comm -23 <(echo "$domains") <(echo "$domains_in_toplist"))"
        awk '{print $0 " (toplist)"}' <<< "$domains_in_toplist" >> manual_review.tmp
        # Save invalid entries for rerun
        printf "%s\n" "$domains_in_toplist" >> "$results_file"
        log_event "$domains_in_toplist" toplist
    fi

    # Collate filtered domains
    printf "%s\n" "$domains" >> retrieved_domains.tmp

    # Collate filtered domains from light sources
    if [[ "$ignore_from_light" != true ]]; then
        printf "%s\n" "$domains" >> retrieved_light_domains.tmp
    fi

    log_event "$domains" pending

    log_source
}

# Function 'build' adds the filtered domains to the raw files and presents
# some basic numbers to the user.
build() {
    if [[ -f manual_review.tmp ]]; then
        # Print domains requiring manual review
        printf "\n\e[1mEntries requiring manual review:\e[0m\n"
        sed 's/(/(\o033[31m/; s/)/\o033[0m)/' manual_review.tmp

        # Send telegram notification
        send_telegram "Entries requiring manual review:\n$(<manual_review.tmp)"
    fi

    # Exit if no new domains to add
    # [ ! -s ] does not seem to work well here
    if ! grep -q '[a-z]' retrieved_domains.tmp; then
        printf "\n\e[1mNo new domains to add.\e[0m\n"
        exit
    fi

    format_file retrieved_domains.tmp

    # Collate filtered subdomains and root domains
    if [[ -f root_domains.tmp ]]; then
        # Find root domains (subdomains stripped off) in the filtered domains
        root_domains="$(comm -12 retrieved_domains.tmp root_domains.tmp)"

        # Collate filtered root domains to exclude from dead check
        printf "%s\n" "$root_domains" >> "$ROOT_DOMAINS"
        # Collate filtered subdomains for dead check
        grep -Ff <(echo "$root_domains") subdomains.tmp >> "$SUBDOMAINS"

        format_file "$ROOT_DOMAINS"
        format_file "$SUBDOMAINS"
    fi

    count_before="$(wc -l < "$RAW")"

    # Add domains to raw file
    cat retrieved_domains.tmp >> "$RAW"
    format_file "$RAW"

    # Add domains to raw light file
    if [[ -f retrieved_light_domains.tmp ]]; then
        cat retrieved_light_domains.tmp >> "$RAW_LIGHT"
        format_file "$RAW_LIGHT"
    fi

    count_after="$(wc -l < "$RAW")"
    printf "\nAdded new domains to blocklist.\nBefore: %s  Added: %s  After: %s\n" \
        "$count_before" "$(( count_after - count_before ))" "$count_after"

    # Mark sources/events as saved in the source log file
    sed -i "/$TIME_FORMAT/s/,pending/,saved/" "$SOURCE_LOG"
    sed -i "/$TIME_FORMAT/s/,pending/,saved/" "$DOMAIN_LOG"
}

# Function 'log_source' prints and logs statistics for each source
# using the variables declared in the 'process_source' function.
log_source() {
    local item
    local status='pending'

    if [[ "$source" == 'Google Search' ]]; then
        item="\"${search_term:0:100}...\""
    fi

    if [[ "$rate_limited" == true ]]; then
        status='eror: rate_limited'
    elif (( raw_count == 0 )); then
        status='error: empty'
    fi

    final_count="$(wc -w <<< "$domains")"
    total_whitelisted_count="$(( whitelisted_count + whitelisted_tld_count ))"
    excluded_count="$(( dead_count + redundant_count + parked_count ))"

    echo "${TIME_FORMAT},${source},${item},${raw_count},\
${final_count},${total_whitelisted_count},${dead_count},${redundant_count},\
${parked_count},${toplist_count},${query_count},${status}" >> "$SOURCE_LOG"

    [[ "$rate_limited" == true ]] && return

    printf "\n\e[1mSource: %s\e[0m\n" "${item:-$source}"

    if [[ "$status" == 'error: empty' ]]; then
        printf "\e[1;31mNo results retrieved. Potential error occurred.\e[0m\n"

        # Send telegram notification
        send_telegram "Source '$source' retrieved no results. Potential error occurred."
    else
        printf "Raw:%4s  Final:%4s  Whitelisted:%4s  Excluded:%4s  Toplist:%4s\n" \
            "$raw_count" "$final_count" "$total_whitelisted_count" \
            "$excluded_count" "$toplist_count"
    fi

    printf "Processing time: %s seconds\n" "$(( "$(date +%s)" - execution_time ))"
    printf "%s\n" "----------------------------------------------------------------------"
}

# Function 'send_telegram' sends a telegram notification with the given message.
#   $DISABLE_TELEGRAM: set to true to not send telegram notifications
#   $1: message body
send_telegram() {
    [[ "$DISABLE_TELEGRAM" == true ]] && return
    curl -sX POST \
        -H 'Content-Type: application/json' \
        -d "{\"chat_id\": \"${TELEGRAM_CHAT_ID}\", \"text\": \"$1\"}" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -o /dev/null
}

# Function 'download_toplist' downloads the toplist and formats it.
# Output:
#   toplist.tmp
download_toplist() {
    [[ -f toplist.tmp ]] && return
    wget -qO - 'https://tranco-list.eu/top-1m.csv.zip' | gunzip - > toplist.tmp \
        || send_telegram "Error downloading toplist."
    awk -F ',' '{print $2}' toplist.tmp > temp && mv temp toplist.tmp
    format_file toplist.tmp
}

# Function 'log_event' logs domain processing events into the domain log.
#   $1: domains to log stored in a variable.
#   $2: event type (dead, whitelisted, etc.)
#   $3: source
log_event() {
    [[ -z "$1" ]] && return  # Return if no domains passed
    local source="$3"
    printf "%s\n" "$1" | awk -v event="$2" -v source="$source" -v time="$(date -u +"%H:%M:%S %d-%m-%y")" \
        '{print time "," event "," $0 "," source}' >> "$DOMAIN_LOG"
}

# Function 'format_file' calls a shell wrapper to standardize the format
# of a file.
#   $1: file to format
format_file() {
    bash functions/tools.sh format "$1"
}

cleanup() {
    # Initialize pending directory if no pending domains to be saved
    find data/pending -type d -empty -delete

    find . -maxdepth 1 -type f -name "*.tmp" -delete
}

# The 'source_<source>' functions are to retrieve results from the
# respective sources.
# Input:
#   $source: name of the source that is used in the console and logs
#   $ignore_from_light: if true, the results are not included in the
#       light version (default is false)
#   $results_file: file path to save retrieved results to be used for
#       further processing
#   $USE_EXISTING: if true, skip the retrieval process and use the
#       existing results files (if found)
# Output:
#   $results_file (if results retrieved)
#
# Note the output results can be in URL form without subfolders.

source_google_search() {
    local source='Google Search'
    local results_file
    local search_term
    local execution_time

    if [[ "$USE_EXISTING" == true ]]; then

        # Use existing retrieved results

        # Loop through the results from each search term
        for results_file in data/pending/domains_google_search_*.tmp; do
            [[ ! -f "$results_file" ]] && return

            execution_time="$(date +%s)"

            # Remove header from file name
            search_term=${results_file#data/pending/domains_google_search_}
            # Remove file extension from file name to get search term
            search_term=${search_term%.tmp}

            process_source
        done
        return
    fi

    # Retrieve new results

    local url='https://customsearch.googleapis.com/customsearch/v1'
    local search_id="$GOOGLE_SEARCH_ID"
    local search_api_key="$GOOGLE_SEARCH_API_KEY"
    local rate_limited=false

    # Install csvkit
    command -v csvgrep &> /dev/null || pip install -q csvkit
    # Install jq
    command -v jq &> /dev/null || apt-get install -yqq jq

    # Get active search times and quote them
    search_terms="$(csvgrep -c 2 -m 'y' -i "$SEARCH_TERMS" | csvcut -c 1 \
        | tail -n +2 | sed 's/.*/"&"/')"

    while read -r search_term; do  # Loop through search terms
        # Stop loop if rate limited
        if [[ "$rate_limited" == true ]]; then
            printf "\n\e[1;31mBoth Google Search API keys are rate limited.\e[0m\n"
            return
        fi
        search_google "$search_term"
    done <<< "$search_terms"
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
    local execution_time
    execution_time="$(date +%s)"

    touch "$results_file"  # Create results file to ensure proper logging

    for start in {1..100..10}; do  # Loop through each page of results
        query_params="cx=${search_id}&key=${search_api_key}&exactTerms=${encoded_search_term}&start=${start}&excludeTerms=scam&filter=0"
        page_results="$(curl -s "${url}?${query_params}")"

        # Use next API key if first key is rate limited
        if [[ "$page_results" == *rateLimitExceeded* ]]; then
            # Stop all searches if second key is also rate limited
            if [[ "$search_id" == "$GOOGLE_SEARCH_ID_2" ]]; then
                readonly rate_limited=true
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
        page_domains="$(jq -r '.items[].link' <<< "$page_results" \
            | awk -F '/' '{print $3}')"
        printf "%s\n" "$page_domains" >> "$results_file"

        # Stop search term if no more pages are required
        (( $(wc -w <<< "$page_domains") < 10 )) && break
    done

    process_source
}

source_dnstwist() {
    local source='dnstwist'
    local results_file="data/pending/domains_${source}.tmp"
    local execution_time
    execution_time="$(date +%s)"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    # Install dnstwist
    pip install -q dnstwist

    # Download and collate NRD feeds
    # (limited to domains registered in the last 30 days)
    # A notification is sent if any link is broken
    {
        wget -qO - 'https://raw.githubusercontent.com/shreshta-labs/newly-registered-domains/main/nrd-1m.csv' \
            || send_telegram "Shreshta's NRD list URL is broken."
        wget -qO - 'https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/nrds.10-onlydomains.txt' \
            | grep -vF '#' || send_telegram "Hagezi's NRD list URL is broken."
        curl -sH 'User-Agent: openSquat-2.1.0' 'https://feeds.opensquat.com/domain-names-month.txt' \
            || send_telegram "openSquat's NRD list URL is broken."
    } > nrd.tmp

    format_file nrd.tmp

    # Remove aleady processed domains to save processing time
    comm -23 nrd.tmp <(sort "$RAW" "$DEAD_DOMAINS" "$PARKED_DOMAINS") > temp
    mv temp nrd.tmp

    # Get the top 15 TLDs from the NRD feed
    # Only 10,000 entries are sampled to save time while providing the same
    # ranking as 100,000 entries and above
    tlds="$(shuf -n 10000 nrd.tmp | awk -F '.' '{print $NF}' | sort | uniq -c \
        | sort -nr | head -n 15 | grep -oE '[[:alpha:]]+')"

    # Remove duplicate targets from targets file
    awk -F ',' '!seen[$1]++' "$PHISHING_TARGETS" \
        > temp && mv temp "$PHISHING_TARGETS"

    # Get targets, ignoring disabled ones
    targets="$(csvgrep -c 5 -m 'y' -i "$PHISHING_TARGETS" | tail -n +2 \
        | awk -F ',' '{print $1}')"

    # Run dnstwist and collate results
    while read -r domain; do
        # Get existing counts
        row="$(awk -v domain="$domain" -F ',' '$1 == domain' "$PHISHING_TARGETS")"
        count="$(awk -F ',' '{print $3}' <<< "$row" || printf "0")"
        runs="$(awk -F ',' '{print $4}' <<< "$row" || printf "0")"
        counts_run="$(awk -F ',' '{print $2}' <<< "$row" || printf "0")"

        # Run dnstwist
        results="$(dnstwist "${domain}.com" -f list)"

        # Append TLDs to results
        while read -r tld; do
            printf "%s\n" "$results" | sed "s/.com/.${tld}/" >> results.tmp
        done <<< "$tlds"

        new_count="$(( "$(wc -w <<< "$results")" + count ))"
        new_runs="$(( runs + 1 ))"
        new_counts_run="$(( new_count / new_runs ))"

        sed -i "s/${domain},${counts_run},${count},${runs}/${domain},${new_counts_run},${new_count},${new_runs}/" "$TARGETS"
    done <<< "$targets"

    # Append TLDs
    while read -r tld; do
        sed "s/.com/.${tld}/" results.tmp >> results_with_tlds.tmp
    done < tld.tmp

    format_file results_with_tlds.tmp

    # Find matching NRDs
    comm -12 results_with_tlds.tmp nrd.tmp > "$results_file"

    # Include common regex matches for phishing domains since there is no
    # permanent place to implement yet
    # (also because dnstwist has a higher chance of false positives for
    # domains less than 5 letters)
    {
        printf -- "(^|-)usps|usps-\n"  # USPS
        printf -- "-evri|evri-\n"  # Evri
        printf -- "(^|-)fedex|fedex(-|\.)\n"  # FedEx
    } > regex.tmp

    grep -Ef regex.tmp -- nrd.tmp >> $results_file

    process_source
}

source_manual() {
    local source='Manual'
    local results_file='data/pending/domains_manual.tmp'
    local execution_time

    # Return if results file not found (source is the file itself)
    [[ ! -f "$results_file" ]] && return

    execution_time="$(date +%s)"

    grep -oE '[[:alnum:].-]+\.[[:alnum:]-]{2,}' "$results_file" > domains.tmp
    mv domains.tmp "$results_file"

    process_source
}

source_aa419() {
    local source='aa419.org'
    local results_file="data/pending/domains_${source}.tmp"
    local execution_time
    execution_time="$(date +%s)"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://api.aa419.org/fakesites'
    local query_params
    query_params="1/500?fromadd=$(date +'%Y')-01-01&Status=active&fields=Domain"

    # Install jq
    command -v jq &> /dev/null || apt-get install -yqq jq

    curl -sH "Auth-API-Id:${AA419_API_ID}" "${url}/${query_params}" \
        | jq -r '.[].Domain' >> "$results_file"  # Trailing slash breaks API call

    process_source
}

source_guntab() {
    local source='guntab.com'
    local ignore_from_light=true
    local results_file="data/pending/domains_${source}.tmp"
    local execution_time
    execution_time="$(date +%s)"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://www.guntab.com/scam-websites'
    curl -s "${url}/" \
        | grep -zoE '<table class="datatable-list table">.*</table>' \
        | grep -aoE '[[:alnum:].-]+\.[[:alnum:]-]{2,}$' > "$results_file"
        # Note results are not sorted by time added

    process_source
}

source_petscams() {
    local source='petscams.com'
    local results_file="data/pending/domains_${source}.tmp"
    local execution_time
    execution_time="$(date +%s)"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url="https://petscams.com"
    for page in {2..21}; do  # Loop through 20 pages
        curl -s "${url}/" \
            | grep -oE '<a href="https://petscams.com/[[:alpha:]-]+/[[:alnum:].-]+-[[:alnum:]-]{2,}/">' \
            | sed 's/<a href="https:\/\/petscams.com\/[[:alpha:]-]\+\///;
                s/-\?[0-9]\?\/">//; s/-/./g' >> "$results_file"
        url="https://petscams.com/page/${page}"  # Add '/page' after first run
    done

    process_source
}

source_scamdirectory() {
    local source='scam.directory'
    local results_file="data/pending/domains_${source}.tmp"
    local execution_time
    execution_time="$(date +%s)"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://scam.directory/category'
    curl -s "${url}/" \
        | grep -oE 'href="/[[:alnum:].-]+-[[:alnum:]-]{2,}" title' \
        | sed 's/href="\///; s/" title//; s/-/./g; 301,$d' > "$results_file"
        # Keep only first 300 results

    process_source
}

source_scamadviser() {
    local source='scamadviser.com'
    local results_file="data/pending/domains_${source}.tmp"
    local page_results
    local execution_time
    execution_time="$(date +%s)"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    touch "$results_file"  # Create results file to ensure proper logging

    local url='https://www.scamadviser.com/articles'
    for page in {1..20}; do  # Loop through pages
        page_results="$(curl -s "${url}?p=${page}")"  # Trailing slash breaks curl

        # Stop if page has an error (scamadviser occasionally has broken pages)
        [[ ! "$page_results" == *article* ]] && break

        grep -oE '<div class="articles">.*<div>Read more</div>' <<< "$page_results" \
            | grep -oE '[A-Z][[:alnum:].-]+\.[[:alnum:]-]{2,}' >> "$results_file"
    done

    process_source
}

source_dfpi() {
    local source='dfpi.ca.gov'
    local ignore_from_light=true
    local results_file="data/pending/domains_${source}.tmp"
    local execution_time
    execution_time="$(date +%s)"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://dfpi.ca.gov/crypto-scams'
    curl -s "${url}/" \
        | grep -oE '<td class="column-5">\s*(<a href=")?(https?://)?[[:alnum:].-]+\.[[:alnum:]-]{2,}' \
        | sed 's/<td class="column-5">//; s/<a href="//; 31,$d' > "$results_file"
        # Keep only first 30 results

    process_source
}

source_stopgunscams() {
    local source='stopgunscams.com'
    local results_file="data/pending/domains_${source}.tmp"
    local execution_time
    execution_time="$(date +%s)"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://stopgunscams.com'
    for page in {1..5}; do
        curl -s "${url}/?page=${page}/" \
            | grep -oE '<h4 class="-ih"><a href="/[[:alnum:].-]+-[[:alnum:]-]{2,}' \
            | sed 's/<h4 class="-ih"><a href="\///; s/-/./g' >> "$results_file"
    done

    process_source
}

# Entry point

trap cleanup EXIT

for file in config/* data/*; do
    format_file "$file"
done

source

build

#!/bin/bash

# Retrieves domains from various sources, processes them and outputs a raw file
# that contains the cumulative domains from all sources over time.

readonly FUNCTION='bash scripts/tools.sh'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly SEARCH_TERMS='config/search_terms.csv'
readonly WHITELIST='config/whitelist.txt'
readonly BLACKLIST='config/blacklist.txt'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'
readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly PHISHING_TARGETS='config/phishing_targets.csv'
readonly SOURCE_LOG='config/source_log.csv'
readonly DOMAIN_LOG='config/domain_log.csv'
TIMESTAMP="$(date -u +"%H:%M:%S %d-%m-%y")"
readonly TIMESTAMP

# Matches example.com, example[.]com, 1.1.1.1
readonly DOMAIN_REGEX='[[:alnum:].-]+\[?\.\]?[[:alnum:]-]+'
# Matches example-com, 1.1.1.1
# https://github.com/jarelllama/Scam-Blocklist/issues/349
readonly DOMAIN_DASH_REGEX='[[:alnum:].-]+-[[:alnum:]-]+'
# Only matches domains
readonly STRICT_DOMAIN_REGEX='[[:alnum:].-]+\.[[:alnum:]-]*[a-z]{2,}[[:alnum:]-]*'

readonly -a SOURCES=(
    source_manual
    source_aa419
    source_emerging_threats
    source_fakewebsitebuster
    source_dnstwist
    source_guntab
    source_jeroenguibe
    source_petscams
    source_phishstats
    source_phishstats_nrd
    source_regex
    source_scamdirectory
    source_scamadviser
    source_stopgunscams
    source_google_search
)

# Function 'source' calls on the respective functions of each source to
# retrieve results. The results are then passed to the 'process_source'
# function for further processing.
source() {
    # Check whether to use existing retrieved results
    if [[ -d data/pending ]]; then
        printf "\nUsing existing lists of retrieved results.\n"
        readonly USE_EXISTING=true
    fi

    mkdir -p data/pending

    # Download dependencies here to not bias the processing time of
    # the sources (done in parallel):
    # Install idn (requires sudo) (note -qq does not seem to work here)
    # Call shell wrapper to download toplist
    # Download NRD feed
    { command -v idn &> /dev/null || sudo apt-get install idn > /dev/null; } \
        & $FUNCTION --download-toplist \
        & { [[ "$USE_EXISTING" != true ]] && download_nrd_feed; }
    wait

    # Declare default values and run each source function
    for SOURCE in "${SOURCES[@]}"; do
        # Skip commented out sources
        [[ "$SOURCE" == \#* ]] && continue

        local ignore_from_light=false
        local rate_limited=false
        local query_count=''
        local execution_time

        execution_time="$(date +%s)"

        $SOURCE

        [[ "$USE_EXISTING" == true ]] && continue

        # The Google Search source is processed by individual search terms, not
        # as one source
        [[ "$source" == 'Google Search' ]] && continue

        process_source
    done
}

# Function 'filter' logs the given entries and removes them from the results
# file.
# Input:
#   $1: entries to remove passed in a variable
#   $2: tag given to entries
#   --no-log:   do not log entries into the domain log
#   --preserve: save entries for manual review and for rerun
# Output:
#   Number of entries that were passed
filter() {
    local entries="$1"
    local tag="$2"

    # Return with 0 entries if no entries passed
    [[ -z "$entries" ]] && { printf "0"; return; }

    # Remove entries from results file
    comm -23 "$results_file" <(printf "%s" "$entries") > results.tmp
    mv results.tmp "$results_file"

    if [[ "$3" != '--no-log' ]]; then
       log_domains "$entries" "$tag"
    fi

    if [[ "$3" == '--preserve' ]]; then
        # Save entries for manual review and for rerun
        mawk -v tag="$tag" '{print $0 " (" tag ")"}' <<< "$entries" \
            >> manual_review.tmp
        printf "%s\n" "$entries" >> "${results_file}.tmp"
    fi

    # Return number of entries
    # Note wc -w is used here because wc -l counts empty variables as 1 line
    wc -w <<< "$entries"
}

# Function 'process_source' filters the results retrieved from the caller
# source. The output is a cumulative filtered domains file of all filtered
# domains from all sources in this run.
process_source() {
    [[ ! -f "$results_file" ]] && return

    # Remove http(s):, slashes, and square brackets (this is done here once
    # instead of multiple times in the source functions)
    # Note that this still allows invalid entries to get through so they can be
    # flagged later on.
    sed -i 's/https\?://; s/[/]//g; s/\[//; s/\]//' "$results_file"

    # Convert Unicode to Punycode
    # '--no-tld' to fix 'idn: tld_check_4z: Missing input' error
    idn --no-tld < "$results_file" > results.tmp
    mv results.tmp "$results_file"

    $FUNCTION --format "$results_file"

    # Count number of unfiltered domains pending
    raw_count="$(wc -l < "$results_file")"

    # Remove known dead domains (includes subdomains)
    dead="$(comm -12 <(sort "$DEAD_DOMAINS") "$results_file")"
    dead_count="$(filter "$dead" dead --no-log)"
    # Logging disabled as it inflated log size

    # Remove known parked domains (includes subdomains)
    parked="$(comm -12 <(sort "$PARKED_DOMAINS") "$results_file")"
    parked_count="$(filter "$parked" parked --no-log)"
    # Logging disabled as it inflated log size

    # Strip away subdomains
    while read -r subdomain; do  # Loop through common subdomains
        subdomains="$(mawk "/^${subdomain}\./" "$results_file")" || continue

        # Strip subdomains down to their root domains
        sed -i "s/^${subdomain}\.//" "$results_file"

        # Save subdomains and root domains to be filtered later
        printf "%s\n" "$subdomains" >> subdomains.tmp
        printf "%s\n" "$subdomains" | sed "s/^${subdomain}\.//" >> root_domains.tmp

        # Log subdomains excluding 'www' (too many of them)
        log_domains "$(mawk '!/^www\./' <<< "$subdomains")" subdomain
    done < "$SUBDOMAINS_TO_REMOVE"
    sort -u "$results_file" -o "$results_file"

    # Remove domains already in raw file
    comm -23 "$results_file" "$RAW" > results.tmp
    mv results.tmp "$results_file"

    # Log blacklisted domains
    log_domains "$(comm -12 "$BLACKLIST" "$results_file")" blacklist

    # Remove whitelisted domains excluding blacklisted domains
    # Note whitelist matching uses keywords
    whitelisted="$(grep -Ff "$WHITELIST" "$results_file" | grep -vxFf "$BLACKLIST")"
    whitelisted_count="$(filter "$whitelisted" whitelist)"

    # Remove domains with whitelisted TLDs
    # mawk does not work with this expression so grep is intentionally chosen
    # over awk. The same applies for the invalid check below.
    whitelisted_tld="$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' "$results_file")"
    whitelisted_tld_count="$(filter "$whitelisted_tld" tld)"

    # Remove non-domain entries including IP addresses excluding punycode
    invalid="$(grep -vE "^${STRICT_DOMAIN_REGEX}$" "$results_file")"
    # Note invalid entries are not counted
    filter "$invalid" invalid --preserve > /dev/null

    # Remove domains in toplist excluding blacklisted domains
    # Note the toplist does not include subdomains
    in_toplist="$(comm -12 toplist.tmp "$results_file" | grep -vxFf "$BLACKLIST")"
    in_toplist_count="$(filter "$in_toplist" toplist --preserve)"

    # Collate filtered domains
    cat "$results_file" >> retrieved_domains.tmp

    if [[ "$ignore_from_light" != true ]]; then
        # Collate filtered domains from light sources
        cat "$results_file" >> retrieved_light_domains.tmp
    fi

    log_domains "$results_file" unsaved

    log_source

    rm "$results_file"

    if [[ -f "${results_file}.tmp" ]]; then
        # Save entries that are pending manual review for rerun
        mv "${results_file}.tmp" "$results_file"
        $FUNCTION --format "$results_file"
    fi
}

# Function 'build' appends the filtered domains into the raw files and presents
# some basic numbers to the user.
build() {
    # For telegram message
    workflow_url='https://github.com/jarelllama/Scam-Blocklist/actions/workflows/build_deploy.yml'

    if [[ -f manual_review.tmp ]]; then
        # Print domains requiring manual review
        printf "\n\e[1mEntries requiring manual review:\e[0m\n"
        sed 's/(/(\o033[31m/; s/)/\o033[0m)/' manual_review.tmp

        # Send telegram notification
        $FUNCTION --send-telegram \
            "Entries requiring manual review:\n$(<manual_review.tmp)"

        printf "\nTelegram notification sent.\n"
    fi

    $FUNCTION --format retrieved_domains.tmp

    # Return if no new domains to add
    if [[ ! -s retrieved_domains.tmp ]]; then
        printf "\n\e[1mNo new domains to add.\e[0m\n"

        [[ "$USE_EXISTING" == true ]] && return
        # Send Telegram update if not using existing results
        $FUNCTION --send-telegram \
            "Run completed. No new domains added.\n${workflow_url}"

        return
    fi

    # Collate only filtered subdomains and root domains into the subdomains
    # file and root domains file
    if [[ -f root_domains.tmp ]]; then
        # Find root domains (subdomains stripped off) in the filtered domains
        root_domains="$(comm -12 <(sort root_domains.tmp) retrieved_domains.tmp)"

        # Check if any filtered root domains are found to avoid appending an
        # empty line
        if [[ -n "$root_domains" ]]; then
            # Collate filtered root domains to exclude from dead check
            printf "%s\n" "$root_domains" >> "$ROOT_DOMAINS"
            sort -u "$ROOT_DOMAINS" -o "$ROOT_DOMAINS"

            # Collate filtered subdomains for dead check
            # grep is used here as mawk does not interpret variables with
            # multiple lines well when matching.
            grep "\.${root_domains}$" subdomains.tmp >> "$SUBDOMAINS"
            sort -u "$SUBDOMAINS" -o "$SUBDOMAINS"
        fi
    fi

    count_before="$(wc -l < "$RAW")"

    # Add domains to raw file
    sort -u retrieved_domains.tmp "$RAW" -o "$RAW"

    if [[ -f retrieved_light_domains.tmp ]]; then
        # Add domains to raw light file
        cat retrieved_light_domains.tmp >> "$RAW_LIGHT"
        $FUNCTION --format "$RAW_LIGHT"
    fi

    count_after="$(wc -l < "$RAW")"
    count_added="$(( count_after - count_before ))"

    printf "\nAdded new domains to blocklist.\nBefore: %s  Added: %s  After: %s\n" \
        "$count_before" "$count_added" "$count_after"

    # Mark sources/events as saved in the log files
    sed -i "/${TIMESTAMP}/s/,unsaved/,saved/" "$SOURCE_LOG"
    sed -i "/${TIMESTAMP}/s/,unsaved/,saved/" "$DOMAIN_LOG"

    [[ "$USE_EXISTING" == true ]] && return
    # Send Telegram update if not using existing results
    $FUNCTION --send-telegram \
        "Run completed. Retrieved ${count_added} domains.\n${workflow_url}"
}

# Function 'log_source' prints and logs statistics for each source using the
# variables declared in the 'process_source' function.
log_source() {
    local item
    local status='unsaved'

    if [[ "$source" == 'Google Search' ]]; then
        item="\"${search_term:0:100}...\""
    fi

    # Check for errors to log
    if [[ "$rate_limited" == true ]]; then
        status='eror: rate_limited'
    elif (( raw_count == 0 )); then
        status='error: empty'
    fi

    final_count="$(wc -l < "$results_file")"
    total_whitelisted_count="$(( whitelisted_count + whitelisted_tld_count ))"
    excluded_count="$(( dead_count + parked_count ))"

    echo "${TIMESTAMP},${source},${item},${raw_count},${final_count},\
${total_whitelisted_count},${dead_count},${parked_count},${in_toplist_count},\
${query_count},${status}" >> "$SOURCE_LOG"

    [[ "$rate_limited" == true ]] && return

    printf "\n\e[1mSource: %s\e[0m\n" "${item:-$source}"

    if [[ "$status" == 'error: empty' ]]; then
        printf "\e[1;31mNo results retrieved. Potential error occurred.\e[0m\n"

        # Send telegram notification
        $FUNCTION --send-telegram \
            "Source '$source' retrieved no results. Potential error occurred."
    else
        printf "Raw:%4s  Final:%4s  Whitelisted:%4s  Excluded:%4s  Toplist:%4s\n" \
            "$raw_count" "$final_count" "$total_whitelisted_count" \
            "$excluded_count" "$in_toplist_count"
    fi

    printf "Processing time: %s second(s)\n" "$(( $(date +%s) - execution_time ))"
    echo "----------------------------------------------------------------------"
}

# Function 'log_domains' calls a shell wrapper to log domain processing events
# into the domain log.
#   $1: domains to log either in a file or variable
#   $2: event type (dead, whitelisted, etc.)
log_domains() {
    $FUNCTION --log-domains "$1" "$2" "$source" "$TIMESTAMP"
}

# Function 'download_nrd_feed' calls a shell wrapper to download the NRD feed.
# Output:
#   nrd.tmp
download_nrd_feed() {
    $FUNCTION --download-nrd-feed

    # Remove already processed domains to save processing time
    comm -23 nrd.tmp <(sort "$RAW" "$DEAD_DOMAINS" "$PARKED_DOMAINS") > temp
    mv temp nrd.tmp
}

cleanup() {
    # Initialize pending directory if no domains to be saved for rerun
    find data/pending -type d -empty -delete

    find . -maxdepth 1 -type f -name "*.tmp" -delete
}

# The 'source_<source>' functions are to retrieve results from the respective
# sources.
# Input:
#   $source:            name of the source to use in the console and logs
#   $ignore_from_light: if true, the results are not included in the light
#                       version (default is false)
#   $results_file:      file path to save retrieved results to be used for
#                       further processing
#   $USE_EXISTING:      if true, skip the retrieval process and use the
#                       existing results files (if found)
# Output:
#   $results_file (if results retrieved)
#
# Note the output results can be in URL form without subfolders.

source_google_search() {
    source='Google Search'

    if [[ "$USE_EXISTING" == true ]]; then
        # Use existing retrieved results
        # Loop through the results from each search term
        for results_file in data/pending/domains_google_search_*.tmp; do
            [[ ! -f "$results_file" ]] && return

            # Set execution time for each individual search term
            execution_time="$(date +%s)"

            # Remove header from file name
            search_term="${results_file#data/pending/domains_google_search_}"
            # Remove file extension from file name to get search term
            search_term="${search_term%.tmp}"

            process_source
        done
        return
    fi

    # Retrieve new results
    local url='https://customsearch.googleapis.com/customsearch/v1'
    local search_id="$GOOGLE_SEARCH_ID"
    local search_api_key="$GOOGLE_SEARCH_API_KEY"

    # Install csvkit
    command -v csvgrep &> /dev/null || pip install -q csvkit
    # Install jq
    command -v jq &> /dev/null || apt-get install -qq jq

    # Get active search terms
    # csvkit has to be used here as the search terms may contain commas which
    # makes using mawk complicated.
    search_terms="$(csvgrep -c 2 -m 'y' -i "$SEARCH_TERMS" | csvcut -c 1 \
        | tail -n +2)"

    # Loop through search terms
    while read -r search_term; do
        # Stop if rate limited
        if [[ "$rate_limited" == true ]]; then
            printf "\n\e[1;31mBoth Google Search API keys are rate limited.\e[0m\n"
            return
        fi
        search_google "$search_term"
    done <<< "$search_terms"
}

search_google() {
    search_term="${1//\"/}"  # Remove quotes before encoding
    # Replace non-alphanumeric characters with spaces
    encoded_search_term="${search_term//[^[:alnum:]]/%20}"
    results_file="data/pending/domains_google_search_${search_term:0:100}.tmp"
    query_count=0
    # Set execution time for each individual search term
    execution_time="$(date +%s)"

    touch "$results_file"  # Create results file to ensure proper logging

    # Loop through each page of results
    for start in {1..100..10}; do
    # Indentation intentionally lacking here
    params="cx=${search_id}&key=${search_api_key}&exactTerms=${encoded_search_term}&start=${start}&excludeTerms=scam&filter=0"
    page_results="$(curl -sS "${url}?${params}")"

        (( query_count++ ))

        # Use next API key if first key is rate limited
        if [[ "$page_results" == *rateLimitExceeded* ]]; then
            # Stop all searches if second key is also rate limited
            if [[ "$search_id" == "$GOOGLE_SEARCH_ID_2" ]]; then
                rate_limited=true
                break
            fi

            printf "\n\e[1mGoogle Search rate limited. Switching API keys.\e[0m\n"

            # Switch API keys
            readonly search_api_key="$GOOGLE_SEARCH_API_KEY_2"
            readonly search_id="$GOOGLE_SEARCH_ID_2"

            # Continue to next page (current rate limited page is not repeated)
            continue
        fi

        # Stop search term if page has no results
        jq -e '.items' &> /dev/null <<< "$page_results" || break

        # Get domains from each page
        page_domains="$(jq -r '.items[].link' <<< "$page_results" \
            | mawk -F '/' '{print $3}')"
        printf "%s\n" "$page_domains" >> "$results_file"

        # Stop search term if no more pages are required
        (( $(wc -w <<< "$page_domains") < 10 )) && break
    done

    process_source
}

source_dnstwist() {
    source='dnstwist'
    results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    # Install dnstwist
    command -v dnstwist > /dev/null || pip install -q dnstwist

    # Get the top 15 TLDs from the NRD feed
    # Only 10,000 entries are sampled to save time while providing the same
    # ranking as 100,000 entries and above.
    tlds="$(shuf -n 10000 nrd.tmp | mawk -F '.' '{print $NF}' | sort | uniq -c \
        | sort -nr | head -n 15 | mawk '{print $2}')"

    # Remove duplicate targets from targets file
    mawk -F ',' '!seen[$1]++' "$PHISHING_TARGETS" > temp
    mv temp "$PHISHING_TARGETS"

    # Get targets ignoring disabled ones
    targets="$(mawk -F ',' '$5 != "y" {print $1}' "$PHISHING_TARGETS" | tail -n +2)"

    # Loop through the targets
    while read -r domain; do
        # Get row and counts for the target domain
        row="$(mawk -F ',' -v domain="$domain" \
            '$1 == domain {printf $1","$2","$3","$4}' "$PHISHING_TARGETS")"
        count="$(mawk -F ',' '{print $3}' <<< "$row")"
        runs="$(mawk -F ',' '{print $4}' <<< "$row")"

        # Run dnstwist
        results="$(dnstwist "${domain}.com" -f list)"

        # Append TLDs to results
        while read -r tld; do
            printf "%s\n" "$results" | sed "s/\.com/.${tld}/" >> results.tmp
        done <<< "$tlds"
        sort -u results.tmp -o results.tmp

        # Get matching NRDs
        comm -12 results.tmp nrd.tmp > temp
        mv temp results.tmp

        # Collate results
        cat results.tmp >> "$results_file"

        # Update counts for the target domain
        count="$(( count + $(wc -l < results.tmp) ))"
        (( runs++ ))
        counts_run="$(( count / runs ))"
        sed -i "s/${row}/${domain},${counts_run},${count},${runs}/" \
            "$PHISHING_TARGETS"

        # Reset results file for the next target domain
        rm results.tmp
    done <<< "$targets"
}

source_regex() {
    source='Regex'
    ignore_from_light=true
    results_file='data/pending/domains_regex.tmp'

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    # Remove duplicate targets from targets file
    mawk -F ',' '!seen[$1]++' "$PHISHING_TARGETS" > temp
    mv temp "$PHISHING_TARGETS"

    # Get targets ignoring disabled ones
    targets="$(mawk -F ',' '$10 == "n" {print $1}' "$PHISHING_TARGETS")"

    # Loop through the targets
    while read -r domain; do
        # Get row and counts for the target domain
        row="$(mawk -F ',' -v domain="$domain" \
            '$1 == domain {printf $6","$7","$8","$9}' "$PHISHING_TARGETS")"
        count="$(mawk -F ',' '{print $3}' <<< "$row")"
        runs="$(mawk -F ',' '{print $4}' <<< "$row")"

        # Get regex of target
        pattern="$(mawk -F ',' '{printf $1}' <<< "$row")"
        escaped_domain="${domain//[.]/\\.}"
        regex="${pattern/&/${escaped_domain}}"

        # Get matches in NRD feed
        results="$(mawk "/${regex}/" nrd.tmp | sort -u)"

        # Collate results
        printf "%s\n" "$results" >> "$results_file"

        # Escape periods and backslashes
        row="$(printf "%s" "$row" | sed 's/[.\]/\\&/g')"
        # Escape '&', periods and backslashes
        pattern="$(printf "%s" "$pattern" | sed 's/[&.\]/\\&/g')"

        # Update counts for the target domain
        count="$(( count + $(wc -w <<< "$results") ))"
        (( runs++ ))
        counts_run="$(( count / runs ))"
        sed -i "/${domain}/s/${row}/${pattern},${counts_run},${count},${runs}/" \
            "$PHISHING_TARGETS"
    done <<< "$targets"
}

source_phishstats() {
    source='PhishStats'
    ignore_from_light=true
    results_file='data/pending/domains_phishstats.tmp'

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://phishstats.info/phish_score.csv'
    # Get URLs with no subdirectories, exclude IP addresses and extract domains
    # (?=/?\"?$) is lookahead that matches an optional slash followed by an
    # optional end quote at the end of the line.
    curl -sSL "$url" | mawk -F ',' '{print $3}' \
        | grep -Po "^\"?https?://\K${STRICT_DOMAIN_REGEX}(?=/?\"?$)" \
        | sort -u -o "$results_file"

    # Get matching NRDs for light version (Unicode ignored)
    comm -12 "$results_file" nrd.tmp > phishstats_nrds.tmp
}

source_phishstats_nrd() {
    # For the light version
    # Only includes domains found in the NRD feed
    source='PhishStats (NRDs)'
    results_file='data/pending/domains_phishstats_nrd.tmp'

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    mv phishstats_nrds.tmp "$results_file"
}

source_manual() {
    source='Manual'
    results_file='data/pending/domains_manual.tmp'

    # Process only if file is found (source is the file itself)
    [[ -f "$results_file" ]] && process_source
}

source_aa419() {
    source='aa419.org'
    results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    # Install jq
    command -v jq &> /dev/null || apt-get install -qq jq

    local url='https://api.aa419.org/fakesites'
    # Trailing slash intentionally omitted
    curl -sSH "Auth-API-Id:${AA419_API_ID}" "${url}/0/250?Status=active" \
        --retry 2 --retry-all-errors | jq -r '.[].Domain' > "$results_file"
}

source_emerging_threats() {
    source='Emerging Threats'
    results_file='data/pending/domains_emerging_threats.tmp'

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://raw.githubusercontent.com/jarelllama/Emerging-Threats/main/data/phishing.txt'
    curl -sSL --retry 2 --retry-all-errors "$url" -o "$results_file"
}

source_fakewebsitebuster() {
    source='fakewebsitebuster.com'
    results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://fakewebsitebuster.com/category/website-reviews'
    # Regarding grep pipe errors, see:
    # https://github.com/jarelllama/Scam-Blocklist/issues/349
    curl -sS --retry 2 --retry-all-errors "${url}/" \
        | grep -oE 'rel="bookmark">.*</a></h2>' \
        | grep -oE "([0-9]|[A-Z])${DOMAIN_REGEX}" \
        | head -n 50 > "$results_file"  # Keep only newest 50 results
}

source_guntab() {
    source='guntab.com'
    ignore_from_light=true
    results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://www.guntab.com/scam-websites'
    curl -sS --retry 2 --retry-all-errors "${url}/" \
        | grep -zoE '<table class="datatable-list table">.*</table>' \
        | grep -aoE "${DOMAIN_REGEX}$" > "$results_file"
        # Note results are not sorted by time added
}

source_jeroenguibe() {
    source='jeroengui.be'
    results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url
    url='https://file.jeroengui.be/scam/last_month.txt'  # TODO: change to weekly feed and use curl URL globbing
    curl -sSL --retry 2 --retry-all-errors "$url" >> results.tmp
    url='https://file.jeroengui.be/phishing/last_week.txt'
    curl -sSL --retry 2 --retry-all-errors "$url" >> results.tmp

    # Get URLs with no subdirectories, exclude IP addresses and extract domains
    grep -Po "^https?://\K${STRICT_DOMAIN_REGEX}(?=/?$)" results.tmp \
        -o "$results_file"

    rm results.tmp
}

source_petscams() {
    source='petscams.com'
    results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://petscams.com'
    # First page must not have '/page'
    curl -sS --retry 2 --retry-all-errors "${url}/" >> results.tmp
    curl -sSZ --retry 2 --retry-all-errors "${url}/page/[2-15]/" >> results.tmp

    # Each page in theory should return 15 domains, but the regex also matches
    # domains under 'Latest Articles' at the bottom of the page, so the number
    # of domains returned per page may be >15.
    # [:alpha:] is used because [a-z] does not seem to work here
    # Matching '/">' ensures not matching false positives
    grep -Po "<a href=\"https://petscams.com/[[:alpha:]-]+/\K${DOMAIN_DASH_REGEX}(?=/\">)" \
        results.tmp | mawk '{sub(/-[0-9]$/, "", $0);
        gsub(/-/, ".", $0); print $0}' > "$results_file"

    rm results.tmp
}

source_scamdirectory() {
    source='scam.directory'
    results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://scam.directory/category'
    curl -sS --retry 2 --retry-all-errors "${url}/" \
        | grep -Po "href=\"/\K${DOMAIN_DASH_REGEX}(?=\" title)" \
        | mawk 'NR<=100 {gsub(/-/, ".", $0); print $0}' > "$results_file"
        # Keep only newest 100 results
}

source_scamadviser() {
    source='scamadviser.com'
    results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://www.scamadviser.com/articles'
    # Regarding grep pipe errors, see:
    # https://github.com/jarelllama/Scam-Blocklist/issues/349
    # Trailing slash intentionally omitted
    curl -sSZ --retry 2 --retry-all-errors "${url}?p=[1-15]" \
        | grep -oE '<h2 class="mb-0">.*</h2>' \
        | grep -oE "([0-9]|[A-Z])${DOMAIN_REGEX}" > "$results_file"
}

source_stopgunscams() {
    source='stopgunscams.com'
    results_file="data/pending/domains_${source}.tmp"

    [[ "$USE_EXISTING" == true ]] && { process_source; return; }

    local url='https://stopgunscams.com'
    # Trailing slash intentionally omitted
    curl -sS --retry 2 --retry-all-errors "${url}/sitemap" \
        | grep -Po "class=\"rank-math-html-sitemap__link\">\K${DOMAIN_REGEX}" \
        | head -n 100 > "$results_file"  # Keep only newest 100 results
}

# Entry point

trap cleanup EXIT

$FUNCTION --format-all

source

build

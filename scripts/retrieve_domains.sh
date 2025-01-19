#!/bin/bash

# Retrieve domains from the various sources, process them and output a raw file
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
# Note the [[:alnum:]] in the front and end of the main domain body is to
# prevent matching entries that start or end with a dash or period.
readonly DOMAIN_REGEX='[[:alnum:]][[:alnum:].-]*[[:alnum:]]\.[[:alnum:]-]*[a-z]{2,}[[:alnum:]-]*'
# Array of sources used to retrieve domains
readonly -a SOURCES=(
    source_165antifraud
    source_aa419
    source_coi.gov.cz
    source_cybersquatting
    source_dga_detector
    source_emerging_threats
    source_fakewebshoplisthun
    source_jeroengui
    source_jeroengui_nrd
    source_gridinsoft
    source_malwaretips
    source_manual
    source_pcrisk
    source_phishstats
    source_phishstats_nrd
    source_puppyscams
    source_regex
    source_safelyweb
    source_scamadviser
    source_scamdirectory
    source_stopgunscams
    source_viriback_tracker
    source_vzhh
    source_google_search
)

main() {
    # Check whether to use existing results in data/pending
    if [[ -d data/pending ]]; then
        printf "\nUsing existing lists of retrieved results.\n"
        readonly USE_EXISTING_RESULTS=true
    else
        mkdir -p data/pending
    fi

    # Download dependencies (done in parallel):
    # Install idn (requires sudo) (note -qq does not seem to work here)
    # Call shell wrapper to download toplist.tmp and nrd.tmp
    { command -v idn > /dev/null || sudo apt-get install idn > /dev/null; } \
        & $FUNCTION --download-toplist \
        & { [[ "$USE_EXISTING_RESULTS" != true ]] \
        && $FUNCTION --download-nrd-feed; }
    wait

    # Remove already processed NRDs to save processing time
    comm -23 nrd.tmp <(sort "$RAW" "$DEAD_DOMAINS" "$PARKED_DOMAINS") > temp
    mv temp nrd.tmp

    retrieve_source_results

    build_raw_file
}

# Run each source function to retrieve domains to pass to the source processing
# function.
retrieve_source_results() {
    local source

    for source in "${SOURCES[@]}"; do
        # Skip commented out sources
        [[ "$source" == \#* ]] && continue

        # Declare default values
        local source_name
        local source_url
        local source_results
        local ignore_from_light=false
        local rate_limited=false
        local query_count
        local execution_time
        execution_time="$(date +%s)"

        # Run source
        $source

        # Process source except for Google Search as that is handled per
        # search term
        [[ "$source_name" != 'Google Search' ]] && process_source_results
    done
}

# Called by the source processing function to remove entries from the source
# results file and log them into the domain log.
# Input:
#   $1: entries to remove passed in a variable
#   $2: tag to be shown in log
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
    comm -23 "$source_results" <(printf "%s" "$entries") > results.tmp
    mv results.tmp "$source_results"

    if [[ "$3" != '--no-log' ]]; then
       log_domains "$entries" "$tag"
    fi

    if [[ "$3" == '--preserve' ]]; then
        # Save entries for manual review and for rerun
        mawk -v tag="$tag" '{print $0 " (" tag ")"}' <<< "$entries" \
            >> entries_for_review.tmp
        printf "%s\n" "$entries" >> "${source_results}.tmp"
    fi

    # Return number of entries
    # Note wc -w is used here because wc -l counts empty variables as 1 line
    wc -w <<< "$entries"
}

# Filter the results from the source and append the domains to
# all_retrieved_domains.tmp/all_retrieved_light_domains.tmp.
process_source_results() {
    # TODO: how to do error handling for sources with no results/no results
    # file?
    [[ ! -f "$source_results" ]] && return

    local raw_count dead_count parked_count whitelisted_count
    local whitelisted_tld_count in_toplist_count

    # TODO: check what else can be moved here from the source functions
    # Remove http(s): and square brackets (this is done here once instead of
    # multiple times in the source functions)
    # Note that this still allows invalid entries like entries with subfolders
    # to get through so they can be flagged later on.
    sed -i 's/https\?:\/\///; s/\[//; s/\]//' "$source_results"

    # Convert Unicode to Punycode
    # '--no-tld' to fix 'idn: tld_check_4z: Missing input' error
    idn --no-tld < "$source_results" > results.tmp
    mv results.tmp "$source_results"

    # Format results file
    $FUNCTION --format "$source_results"

    # Count number of unfiltered domains pending
    raw_count="$(wc -l < "$source_results")"

    # Remove known dead domains (dead domains file is not sorted and includes
    # subdomains)
    dead_count="$(filter \
        "$(comm -12 <(sort "$DEAD_DOMAINS") "$source_results")" dead --no-log)"

    # Remove known parked domains (parked domains file is not sorted and
    # includes subdomains)
    parked_count="$(filter \
        "$(comm -12 <(sort "$PARKED_DOMAINS") "$source_results")" parked \
        --no-log)"

    # Strip away subdomains
    # Note that using 'while read' does not set the variable 'subdomain' as
    # global.
    local subdomains
    while read -r subdomain; do  # Loop through common subdomains
        subdomains="$(mawk "/^${subdomain}\./" "$source_results")" || continue

        # Strip subdomains down to their root domains
        sed -i "s/^${subdomain}\.//" "$source_results"

        # Save subdomains and root domains to be filtered later
        printf "%s\n" "$subdomains" >> subdomains.tmp
        printf "%s\n" "$subdomains" | sed "s/^${subdomain}\.//" \
            >> root_domains.tmp
    done < "$SUBDOMAINS_TO_REMOVE"
    sort -u "$source_results" -o "$source_results"

    # Remove domains already in raw file
    comm -23 "$source_results" "$RAW" > results.tmp
    mv results.tmp "$source_results"

    # Log blacklisted domains
    # log_domains is used instead of filter as the blacklisted domains should
    # not be removed from the results file.
    log_domains "$(comm -12 "$BLACKLIST" "$source_results")" blacklist

    # Remove whitelisted domains excluding blacklisted domains
    # Note whitelist uses regex matching
    whitelisted_count="$(filter \
        "$(grep -Ef "$WHITELIST" "$source_results" \
        | grep -vxFf "$BLACKLIST")" whitelist)"

    # Remove domains with whitelisted TLDs
    # mawk does not work with this expression so grep is intentionally chosen.
    # The same applies for the invalid check below.
    whitelisted_tld_count="$(filter \
        "$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' \
        "$source_results")" whitelisted_tld)"

    # Remove non-domain entries including IP addresses excluding Punycode
    # Redirect output to /dev/null as the invalid entries count is not needed
    filter "$(grep -vE "^${DOMAIN_REGEX}$" "$source_results")" \
        invalid --preserve > /dev/null

    # Remove domains in toplist excluding blacklisted domains
    # Note the toplist does not include subdomains
    in_toplist_count="$(filter \
        "$(comm -12 toplist.tmp "$source_results" \
        | grep -vxFf "$BLACKLIST")" toplist --preserve)"

    # Collate filtered domains
    cat "$source_results" >> all_retrieved_domains.tmp

    if [[ "$ignore_from_light" != true ]]; then
        # Collate filtered domains from light sources
        cat "$source_results" >> all_retrieved_light_domains.tmp
    fi

    log_domains "$source_results" saved

    log_source

    rm "$source_results"

    # TODO: collate entries pending manual review into seperate config file for
    # easier blacklisting/whitelisting: https://github.com/jarelllama/Scam-Blocklist/issues/411
    if [[ -f "${source_results}.tmp" ]]; then
        # Save entries that are pending manual review for rerun
        mv "${source_results}.tmp" "$source_results"
        $FUNCTION --format "$source_results"
    fi
}

# Append filtered domains onto the raw file.
build_raw_file() {
    if [[ -f entries_for_review.tmp ]]; then
        # Print domains requiring manual review
        printf "\n\e[1mEntries requiring manual review:\e[0m\n"
        sed 's/(/(\o033[31m/; s/)/\o033[0m)/' entries_for_review.tmp

        # Send telegram notification
        $FUNCTION --send-telegram \
            "Retrieval: entries requiring manual review\n\n$(<entries_for_review.tmp)"

        printf "\nTelegram notification sent.\n"
    fi

    $FUNCTION --format all_retrieved_domains.tmp

    # Return if no new domains to add
    if [[ ! -s all_retrieved_domains.tmp ]]; then
        printf "\n\e[1mNo new domains to add.\e[0m\n"

        [[ "$USE_EXISTING_RESULTS" == true ]] && return
        # Send Telegram update if not using existing results
        $FUNCTION --send-telegram \
            "Retrieval: no new domains added"

        return
    fi

    # TODO: how to save subdomains of domains manually blacklisted after review?
    # https://github.com/jarelllama/Scam-Blocklist/issues/412
    #
    # Collate only filtered subdomains and root domains into the subdomains
    # file and root domains file
    if [[ -f root_domains.tmp ]]; then
        local root_domains

        # Find root domains (subdomains stripped off) in the filtered domains
        root_domains="$(comm -12 <(sort root_domains.tmp) \
            all_retrieved_domains.tmp)"

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

    local count_before count_after count_added

    count_before="$(wc -l < "$RAW")"

    # Add domains to raw file
    sort -u all_retrieved_domains.tmp "$RAW" -o "$RAW"

    if [[ -f all_retrieved_light_domains.tmp ]]; then
        # Add domains to raw light file
        cat all_retrieved_light_domains.tmp >> "$RAW_LIGHT"
        $FUNCTION --format "$RAW_LIGHT"
    fi

    count_after="$(wc -l < "$RAW")"
    count_added="$(( count_after - count_before ))"

    printf "\nAdded new domains to raw file.\nBefore: %s  Added: %s  After: %s\n" \
        "$count_before" "$count_added" "$count_after"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return
    # Send Telegram update if not using existing results
    $FUNCTION --send-telegram \
        "Retrieval: added ${count_added} domains"
}

# Print and log statistics for each source after the source processing
# function.
log_source() {
    local item final_count total_whitelisted_count excluded_count
    local status='saved'

    if [[ "$source_name" == 'Google Search' ]]; then
        item="\"${search_term:0:100}...\""
    fi

    # Check for errors to log
    if [[ "$rate_limited" == true ]]; then
        status='ERROR: rate_limited'
    elif (( raw_count == 0 )); then
        status='ERROR: empty'
    fi

    final_count="$(wc -l < "$source_results")"
    total_whitelisted_count="$(( whitelisted_count + whitelisted_tld_count ))"
    excluded_count="$(( dead_count + parked_count ))"

    echo "$(TZ=Asia/Singapore date +"%H:%M:%S %d-%m-%y"),${source_name},${item},\
${raw_count},${final_count},${total_whitelisted_count},${dead_count},\
${parked_count},${in_toplist_count},${query_count},${status}" >> "$SOURCE_LOG"

    [[ "$rate_limited" == true ]] && return

    printf "\n\e[1mSource: %s\e[0m\n" "${item:-$source_name}"

    if [[ "$status" == 'ERROR: empty' ]]; then
        printf "\e[1;31mNo results retrieved. Potential error occurred.\e[0m\n"

        # Send telegram notification
        $FUNCTION --send-telegram \
            "Warning: '$source_name' retrieved no results. Potential error occurred."
    else
        printf "Raw:%4s  Final:%4s  Whitelisted:%4s  Excluded:%4s  Toplist:%4s\n" \
            "$raw_count" "$final_count" "$total_whitelisted_count" \
            "$excluded_count" "$in_toplist_count"
    fi

    printf "Processing time: %s second(s)\n" "$(( $(date +%s) - execution_time ))"
    echo "----------------------------------------------------------------------"
}

# Call a shell wrapper to to log domain processing events into the domain log.
#   $1: domains to log either in a file or variable
#   $2: event type (dead, whitelisted, etc.)
log_domains() {
    $FUNCTION --log-domains "$1" "$2" "$source_name"
}

cleanup() {
    # Initialize pending directory if no domains to be saved for rerun
    find data/pending -type d -empty -delete

    find . -maxdepth 1 -type f -name "*.tmp" -delete
}

# The 'source_<source>' functions retrieve results from the respective sources.
# Input:
#   $source_name:          name of the source to use in the console and logs
#   $ignore_from_light:    if true, the results are not included in the light
#                          version (default is false)
#   $source_results:       file path to save retrieved results for the source
#                          processing function
#   $USE_EXISTING_RESULTS: if true, skip the retrieval process and use the
#                          existing results files
# Output:
#   $source_results (if results retrieved)
#
# Note the output results can be in URL form without subfolders.

source_google_search() {
    # Last checked: 23/12/24
    source_name='Google Search'
    source_url='https://customsearch.googleapis.com/customsearch/v1'
    local search_id="$GOOGLE_SEARCH_ID"
    local search_api_key="$GOOGLE_SEARCH_API_KEY"
    local search_term encoded_search_term

    if [[ "$USE_EXISTING_RESULTS" == true ]]; then
        # Use existing retrieved results
        # Loop through the results from each search term
        for source_results in data/pending/google_search_*.tmp; do
            [[ ! -f "$source_results" ]] && return

            # Set execution time for each individual search term
            execution_time="$(date +%s)"

            # Remove header from file name
            search_term="${source_results#data/pending/google_search_}"
            # Remove file extension from file name to get search term
            search_term="${search_term%.tmp}"

            process_source_results
        done
        return
    fi

    # Install csvkit
    command -v csvgrep > /dev/null || pip install -q csvkit
    # Install jq
    command -v jq > /dev/null || apt-get install -qq jq

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
    # Last checked: 05/01/25
    search_term="${1//\"/}"  # Remove quotes before encoding
    # Replace non-alphanumeric characters with spaces
    encoded_search_term="${search_term//[^[:alnum:]]/%20}"
    search_term="${search_term//\//}"  # Remove slashes for file creation
    source_results="google_search_${search_term:0:100}.tmp"
    query_count=0
    # Set execution time for each individual search term
    execution_time="$(date +%s)"

    touch "$source_results"  # Create results file to ensure proper logging

    # Loop through each page of results
    for start in {1..100..10}; do
    # Indentation intentionally lacking here
    # Restrict to results from the last 30 days
    local params="cx=${search_id}&key=${search_api_key}&exactTerms=${encoded_search_term}&dateRestrict=m1&sort=date&start=${start}&filter=0"
    local page_results
    page_results="$(curl -sS "${source_url}?${params}")"

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
        printf "%s\n" "$page_domains" >> "$source_results"

        # Stop search term if no more pages are required
        (( $(wc -w <<< "$page_domains") < 10 )) && break
    done

    process_source_results
}

source_cybersquatting() {
    # Last checked: 23/12/24
    source_name='Cybersquatting'
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    local tlds row count runs results

    # Install dnstwist
    command -v dnstwist > /dev/null || pip install -q dnstwist

    # Install URLCrazy and dependencies
    git clone -q https://github.com/urbanadventurer/urlcrazy.git
    command -v ruby > /dev/null || apt-get install -qq ruby ruby-dev
    # sudo is needed for gem
    sudo gem install --silent json colorize async async-dns async-http

    # Get the majority of TLDs from the NRD feed for dnstwist.
    # This is not needed for URLCrazy as that already checks for
    # alternate TLDs.
    # The top 500 is a good number to avoid invalid TLDs.
    tlds="$(mawk -F '.' '{print $NF}' nrd.tmp | sort | uniq -c \
        | sort -nr | head -n 500 | mawk '{print $2}')"

    # Loop through phishing targets
    while read -r domain; do
        # Get info of the target domain
        row="$(mawk -F ',' -v domain="$domain" \
            '$1 == domain {printf $1","$2","$3}' "$PHISHING_TARGETS")"
        count="$(mawk -F ',' '{print $2}' <<< "$row")"
        runs="$(mawk -F ',' '{print $3}' <<< "$row")"

        # Run dnstwist
        results="$(dnstwist "${domain}.com" -f list)"

        # Append TLDs to dnstwist results
        # Note the dnstwist --tld argument only replaces the TLDs of the
        # original domain.
        while read -r tld; do
            printf "%s\n" "$results" | sed "s/\.com/.${tld}/" >> results.tmp
        done <<< "$tlds"

        # Run URLCrazy (bash does not work)
        ./urlcrazy/urlcrazy -r "${domain}.com" -f CSV \
            | mawk -F ',' '!/"Original"/ {print $2}' \
            | grep -oE "$DOMAIN_REGEX" >> results.tmp

        sort -u results.tmp -o results.tmp

        # Get matching NRDs
        comm -12 results.tmp nrd.tmp > temp
        mv temp results.tmp

        # Collate results
        cat results.tmp >> "$source_results"

        # Update counts for the target domain
        count="$(( count + $(wc -l < results.tmp) ))"
        (( runs++ ))
        sed -i "s/${row}/${domain},${count},${runs}/" \
            "$PHISHING_TARGETS"

        # Reset results file for the next target domain
        rm results.tmp

    done <<< "$(mawk -F ',' '$4 == "y" {print $1}' "$PHISHING_TARGETS")"

    rm -rf urlcrazy
}

source_dga_detector() {
    # Last checked: 23/12/24
    source_name='DGA Detector'
    ignore_from_light=true
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    # Keep only NRDs with more than 12 characters
    mawk 'length($0) > 12' nrd.tmp > domains.tmp

    git clone -q https://github.com/exp0se/dga_detector --depth 1
    pip install -q tldextract

    cd dga_detector || return

    # Set detection threshold. DGA domains fall below the threshold set here.
    # A lower threshold lowers the domain yield and reduces false positives.
    # Note that adding domains to big.txt does not seem to affect detection.
    sed -i "s/threshold = model_data\['thresh'\]/threshold = 0.0009/" \
        dga_detector.py

    # Run DGA Detector on remaining NRDs
    python3 dga_detector.py -f ../domains.tmp > /dev/null

    # Extract DGA domains from json output
    jq -r 'select(.is_dga == true) | .domain' dga_domains.json \
        > "../${source_results}"

    cd ..

    rm -rf dga_detector domains.tmp
}

source_regex() {
    # Last checked: 16/01/25
    source_name='Regex'
    ignore_from_light=true
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    local row count runs pattern results

    # Loop through phishing targets
    while read -r domain; do
        # Get info of the target domain
        row="$(mawk -F ',' -v domain="$domain" \
            '$1 == domain {printf $5","$6","$7}' "$PHISHING_TARGETS")"
        count="$(mawk -F ',' '{print $2}' <<< "$row")"
        runs="$(mawk -F ',' '{print $3}' <<< "$row")"
        pattern="$(mawk -F ',' '{printf $1}' <<< "$row")"

        # Get regex of target
        local escaped_domain="${domain//[.]/\\.}"
        local regex="${pattern//&/${escaped_domain}}"

        # Get matches in NRD feed
        results="$(mawk "/${regex}/" nrd.tmp | sort -u)"

        # Collate results
        printf "%s\n" "$results" >> "$source_results"

        # Escape the following: . \ ^ *
        row="$(printf "%s" "$row" | sed 's/[.\^*]/\\&/g')"
        # Escape the following: & . \ ^ *
        pattern="$(printf "%s" "$pattern" | sed 's/[&.\^*]/\\&/g')"

        # Update counts for the target domain
        count="$(( count + $(wc -w <<< "$results") ))"
        (( runs++ ))
        sed -i "/${domain}/s/${row}/${pattern},${count},${runs}/" \
            "$PHISHING_TARGETS"

    done <<< "$(mawk -F ',' '$8 == "y" {print $1}' "$PHISHING_TARGETS")"
}

source_165antifraud() {
    # Last checked: 27/12/24
    # Credit to @tanmarpn for the source idea
    source_name='165 Anti-fraud'
    source_url='https://165.npa.gov.tw/api/article/subclass/3'
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sS "$source_url" \
        | jq --arg year "$(date +%Y)" '.[] | select(.publishDate | contains($year)) | .content' \
        | grep -Po "\\\">(https?://)?\K${DOMAIN_REGEX}" \
        | sort -u -o "$source_results"
}

source_aa419() {
    # Last checked: 23/12/24
    source_name='Artists Against 419'
    source_url='https://api.aa419.org/fakesites'
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    # Install jq
    command -v jq > /dev/null || apt-get install -qq jq

    # Trailing slash intentionally omitted
    curl -sSH "Auth-API-Id:${AA419_API_ID}" "${source_url}/0/250?Status=active" \
        --retry 2 --retry-all-errors | jq -r '.[].Domain' > "$source_results"
}

source_coi.gov.cz() {
    # Last checked: 08/01/25
    source_name='Česká Obchodní Inspekce'
    source_url='https://coi.gov.cz/pro-spotrebitele/rizikove-e-shopy'
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sS --retry 2 --retry-all-errors "${source_url}/" \
        | grep -Po "<span>\K${DOMAIN_REGEX}(?=.*</span>)" \
        > "$source_results"
}

source_emerging_threats() {
    # Last checked: 23/12/24
    source_name='Emerging Threats'
    source_url='https://raw.githubusercontent.com/jarelllama/Emerging-Threats/main/malicious.txt'
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sS "$source_url" | grep -Po "\|\K${DOMAIN_REGEX}" > "$source_results"
}

source_fakewebshoplisthun() {
    # Last checked: 23/12/24
    source_name='FakeWebshopListHUN'
    source_url='https://raw.githubusercontent.com/FakesiteListHUN/FakeWebshopListHUN/refs/heads/main/fakewebshoplist'
    ignore_from_light=true  # Has a few false positives
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sS "$source_url" | grep -Po "^(\|\|)?\K${DOMAIN_REGEX}(?=\^?$)" \
        > "$source_results"
}

source_jeroengui() {
    # Last checked: 03/01/25
    source_name='Jeroengui'
    ignore_from_light=true  # Too many domains
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    source_url='https://file.jeroengui.be/phishing/last_week.txt'
    # Get URLs with no subdirectories (too many link shorteners)
    curl -sS "$source_url" | grep -Po "^https?://\K${DOMAIN_REGEX}(?=/?$)" \
        > "$source_results"

    source_url='https://file.jeroengui.be/malware/last_week.txt'
    curl -sS "$source_url" | grep -Po "^https?://\K${DOMAIN_REGEX}" >> "$source_results"

    source_url='https://file.jeroengui.be/scam/last_week.txt'
    curl -sS "$source_url" | grep -Po "^https?://\K${DOMAIN_REGEX}" >> "$source_results"

    # Get matching NRDs for the light version. Unicode is only processed by the
    # full version.
    comm -12 <(sort "$source_results") nrd.tmp > jeroengui_nrds.tmp
}

source_jeroengui_nrd() {
    # Last checked: 29/12/24
    # For the light version
    # Only includes domains found in the NRD feed
    source_name='Jeroengui (NRDs)'
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    mv jeroengui_nrds.tmp "$source_results"
}

source_gridinsoft() {
    # Last checked: 10/01/25
    source_name='Gridinsoft'
    source_url='https://raw.githubusercontent.com/jarelllama/Blocklist-Sources/refs/heads/main/gridinsoft.txt'
    ignore_from_light=true  # Has a few false positives
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sS "$source_url" | grep -Po "\|\K${DOMAIN_REGEX}" > "$source_results"
}

source_malwaretips() {
    # Last checked: 09/01/25
    source_name='MalwareTips'
    source_url=(
        'https://malwaretips.com/blogs/category/adware'
        'https://malwaretips.com/blogs/category/hijackers'
        'https://malwaretips.com/blogs/category/rogue-software'
    )
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    for source_url in "${source_url[@]}"; do
        curl -sSZL --retry 2 --retry-all-errors "${source_url}/page/[1-15]"
    done | grep -Po "[A-Z0-9][-.]?${DOMAIN_REGEX}(?= [A-Z])" > "$source_results"
}

source_manual() {
    source_name='Manual'
    source_results='data/pending/Manual.tmp'

    # Process only if file is found (source is the file itself)
    [[ -f "$source_results" ]] && process_source_results
}

source_pcrisk() {
    # Last checked: 09/01/25
    source_name='PCrisk'
    source_url='https://www.pcrisk.com/removal-guides'
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    # Matches domain[.]com and domain.com
    curl -sSZ --retry 2 --retry-all-errors "${source_url}?start=[0-15]0" \
        | grep -iPo '>what (kind of (page|website) )?is \K[[:alnum:]][[:alnum:].-]*[[:alnum:]]\[?\.\]?[[:alnum:]-]*[a-z]{2,}[[:alnum:]-]*' \
        > "$source_results"
}

source_phishstats() {
    # Last checked: 29/12/24
    source_name='PhishStats'
    source_url='https://phishstats.info/phish_score.csv'
    ignore_from_light=true  # Too many domains
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    # Get URLs with no subdirectories (some of the URLs use docs.google.com),
    # exclude IP addresses and extract domains.
    # (?=/?\"$) is lookahead that matches an optional slash followed by an end
    # quote at the end of the line.
    curl -sS "$source_url" | mawk -F ',' '{print $3}' \
        | grep -Po "^\"https?://\K${DOMAIN_REGEX}(?=/?\"$)" > "$source_results"

    # Get matching NRDs for the light version. Unicode is only processed by the
    # full version.
    comm -12 <(sort "$source_results") nrd.tmp > phishstats_nrds.tmp
}

source_phishstats_nrd() {
    # Last checked: 23/12/24
    # For the light version
    # Only includes domains found in the NRD feed
    source_name='PhishStats (NRDs)'
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    mv phishstats_nrds.tmp "$source_results"
}

source_puppyscams() {
    # Last checked: 07/01/25
    source_name='PuppyScams.org'
    source_url='https://puppyscams.org'
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSZ --retry 2 --retry-all-errors "${source_url}/?page=[1-15]" \
        | grep -Po " \K${DOMAIN_REGEX}(?=</h4></a>)" > "$source_results"
}

source_safelyweb() {
    # Last checked: 11/01/25
    source_name='SafelyWeb'
    source_url='https://safelyweb.com/scams-database'
    ignore_from_light=true  # Has a few false positives
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSZ --retry 2 --retry-all-errors "${source_url}/?per_page=[1-30]" \
        | grep -Po "<h2 class=\"title\">\K${DOMAIN_REGEX}" > "$source_results"
}

source_scamadviser() {
    # Last checked: 09/01/25
    source_name='ScamAdviser'
    source_url='https://www.scamadviser.com/articles'
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSZ --retry 2 --retry-all-errors "${source_url}?p=[1-15]" \
        | grep -Po "[A-Z0-9][-.]?${DOMAIN_REGEX}(?= ([A-Z]|a ))" > "$source_results"
}

source_scamdirectory() {
    # Last checked: 10/01/25
    source_name='Scam Directory'
    source_url='https://scam.directory/category'
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    # head -n causes grep broken pipe error
    curl -sS --retry 2 --retry-all-errors "${source_url}/" \
        | grep -Po "<span>\K${DOMAIN_REGEX}(?=<br>)" > "$source_results"
}

source_stopgunscams() {
    # Last checked: 07/01/25
    source_name='StopGunScams.com'
    source_url='https://stopgunscams.com'
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSZ --retry 2 --retry-all-errors "${source_url}/page/[1-15]" \
        | grep -Po "title=\"\K${DOMAIN_REGEX}(?=\"></a>)" > "$source_results"
}

source_viriback_tracker() {
    # Last checked: 26/12/24
    source_name='ViriBack C2 Tracker'
    source_url='https://tracker.viriback.com/dump.php'
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sS "$source_url" | mawk -v year="$(date +"%Y")" \
        -F ',' '$4 ~ year {print $2}' \
        | grep -Po "^https?://\K${DOMAIN_REGEX}" > "$source_results"
}

source_vzhh() {
    # Last checked: 27/12/24
    source_name='Verbraucherzentrale Hamburg'
    source_url='https://www.vzhh.de/themen/einkauf-reise-freizeit/einkauf-online-shopping/fake-shop-liste-wenn-guenstig-richtig-teuer-wird'
    source_results="data/pending/${source_name// /_}.tmp"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sS --retry 2 --retry-all-errors "$source_url" \
        | grep -Po "field--item\">\K${DOMAIN_REGEX}(?=</div>)" \
        > "$source_results"
}

# Entry point

trap cleanup EXIT

$FUNCTION --format-all

main

#!/bin/bash

# Retrieve domains from the sources, process them and output a raw file
# that contains the cumulative domains from all sources over time.

# Array of sources used to retrieve domains
readonly -a SOURCES=(
    source_165antifraud
    source_aa419
    source_behindmlm
    source_bugsfighter
    source_coi.gov.cz
    source_crypto_scam_tracker
    source_cybersquatting
    source_dga_detector
    source_emerging_threats
    source_fakewebshoplisthun
    source_greatis
    source_gridinsoft
    source_jeroengui
    source_jeroengui_nrd
    source_malwareurl
    source_manual
    source_pcrisk
    source_phishstats
    source_puppyscams
    source_regex
    source_scamadviser
    source_scamdirectory
    source_scamminder
    source_unit42
    source_viriback_tracker
    source_vzhh
    source_wipersoft
    source_google_search
)
readonly FUNCTION='bash scripts/tools.sh'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly SEARCH_TERMS='config/search_terms.csv'
readonly WHITELIST='config/whitelist.txt'
readonly BLACKLIST='config/blacklist.txt'
readonly REVIEW_CONFIG='config/review_config.csv'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'
readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly PHISHING_TARGETS='config/phishing_detection.csv'
readonly SOURCE_LOG='config/source_log.csv'
# Note the [[:alnum:]] in the front and end of the main domain body is to
# prevent matching entries that start or end with a dash or period.
readonly DOMAIN_REGEX='[[:alnum:]][[:alnum:].-]*[[:alnum:]]\.[[:alnum:]-]*[a-z]{2,}[[:alnum:]-]*'
# Matches domain.com, domain[.]com, and sub[.]domain[.]com
readonly DOMAIN_SQUARE_REGEX='[[:alnum:]][[:alnum:]\[\].-]*[[:alnum:]]\[?\.\]?[[:alnum:]-]*[a-z]{2,}[[:alnum:]-]*'

main() {
    # Check whether to use existing results in the pending directory
    if [[ -d data/pending ]]; then
        printf "\nUsing existing lists of retrieved results.\n"
        readonly USE_EXISTING_RESULTS=true
    else
        readonly USE_EXISTING_RESULTS=false
        mkdir -p data/pending
    fi

    # Install idn2 here instead of in $FUNCTION to not bias source processing
    # time.
    command -v idn2 > /dev/null || sudo apt-get install idn2 > /dev/null

    # Download toplist
    $FUNCTION --download-toplist

    if [[ "$USE_EXISTING_RESULTS" == false ]]; then
        # These dependencies are required by some sources

        # Install jq
        command -v jq > /dev/null || apt-get install -qq jq

        # Download NRD feed
        $FUNCTION --download-nrd-feed
        # Remove already processed NRDs to save processing time
        comm -23 nrd.tmp <(sort "$RAW" "$DEAD_DOMAINS" "$PARKED_DOMAINS") \
            > temp
        mv temp nrd.tmp
    fi

    check_review_file

    retrieve_source_results

    save_domains

    save_subdomains
}

# Check for configured entries in the review config file and add them to the
# whitelist/blacklist. Do nothing for entries that are incorrectly set to both
# blacklist and whitelist.
check_review_file() {
    # Add blacklisted entries to blacklist and remove them from the review file
    mawk -F ',' '$4 == "y" && $5 != "y" { print $2 }' "$REVIEW_CONFIG" \
        | tee >(sort -u - "$BLACKLIST" -o "$BLACKLIST") \
        | xargs -I {} sed -i "/,{},/d" "$REVIEW_CONFIG"

    # Add whitelisted entries to whitelist after formatting to regex and remove
    # them from the review file
    mawk -F ',' '$5 == "y" && $4 != "y" { print $2 }' "$REVIEW_CONFIG" \
        | tee >(mawk '{ gsub(/\./, "\."); print "^" $0 "$" }' \
        | sort -u - "$WHITELIST" -o "$WHITELIST") \
        | xargs -I {} sed -i "/,{},/d" "$REVIEW_CONFIG"
}

# Run each source function to retrieve results collated in "$source_results"
# which are then processed per source by process_source_results.
retrieve_source_results() {
    local source

    for source in "${SOURCES[@]}"; do
        # Skip commented out sources
        [[ "$source" == \#* ]] && continue

        # Error if source_results.tmp from previous source is still present
        if [[ -f source_results.tmp ]]; then
            error 'source_results.tmp not properly cleaned up.'
        fi

        # Initialize source variables
        local source_name=''
        local source_url=''
        local source_results=''
        local exclude_from_light=false
        local rate_limited=false
        local query_count=''
        local execution_time
        execution_time="$(date +%s)"

        # Run source. Always return true to avoid script exiting when no
        # results were retrieved
        $source || true

        # Set source results path based of source name if not explicitly set
        : "${source_results:=data/pending/${source_name// /_}.tmp}"

        # source_results.tmp should be created when the source retrieves new
        # results
        if [[ -f source_results.tmp ]]; then
            # An error would mean a problem with the source function
            if [[ "$USE_EXISTING_RESULTS" == true ]]; then
                error 'source_results.tmp present while USE_EXISTING_RESULTS is true.'
            fi
            # Move source results to source results path
            mv source_results.tmp "$source_results"
        fi

        # The Google Search source processes each search term as one source and
        # handles the source processing logic within its source function.
        [[ "$source_name" == 'Google Search' ]] && continue

        process_source_results
    done
}

# Called by process_source_results to remove entries from the source results
# file and log the entries into the domain log.
# Input:
#   $1: entries to process passed in a variable
#   $2: tag to be shown in the domain log
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
    comm -23 "$source_results" <(printf "%s" "$entries") > temp
    mv temp "$source_results"

    if [[ "$3" != '--no-log' ]]; then
       log_domains "$entries" "$tag"
    fi

    if [[ "$3" == '--preserve' ]]; then
        # Save entries for console output
        mawk -v tag="$tag" '{ print $0 " (" tag ")" }' <<< "$entries" \
            >> entries_for_review.tmp

        # Save entries into review config file
        mawk -v source="$source_name" -v reason="$tag" \
            '{ print source "," $0 "," reason ",," }' <<< "$entries" \
            >> "$REVIEW_CONFIG"

        # Remove duplicates from review config file
        mawk '!seen[$0]++' "$REVIEW_CONFIG" > temp
        mv temp "$REVIEW_CONFIG"

        # Save entries to use in rerun
        printf "%s\n" "$entries" >> "${source_results}.tmp"
    fi

    # Return number of entries
    wc -l <<< "$entries"
}

# Process/filter the results from the source, append the resulting domains to
# all_retrieved_domains.tmp/all_retrieved_light_domains.tmp and save entries
# requiring manual review.
process_source_results() {
    # Skip to next source by returning if no results from this source is found
    [[ ! -f "$source_results" ]] && return

    local raw_count dead_count parked_count whitelisted_count
    local whitelisted_tld_count in_toplist_count

    # Format results file
    $FUNCTION --format "$source_results"

    # Convert URLs to domains and remove square brackets (this is done here
    # once instead of multiple times in the source functions)
    # Note that this still allows invalid entries like entries with subfolders
    # to get through so they can be flagged later on.
    sed -i 's/https\?:\/\///; s/\[//g; s/\]//g' "$source_results"

    # Convert Unicode to Punycode
    $FUNCTION --convert-unicode "$source_results"

    sort -u "$source_results" -o "$source_results"

    # Count number of unfiltered domains
    raw_count="$(wc -l < "$source_results")"

    # Error in case a source wrongly retrieves too many results.
    if (( raw_count > 20000 )); then
        error 'Source is unusually large.'
    fi

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
        subdomains="$(mawk "/^${subdomain}\./" "$source_results")"

        # Continue if no subdomains found
        [[ -z "$subdomains" ]] && continue

        # Strip subdomains down to their root domains
        sed -i "s/^${subdomain}\.//" "$source_results"

        # Save subdomains and root domains to be filtered later
        printf "%s\n" "$subdomains" >> subdomains.tmp
        printf "%s\n" "$subdomains" | sed "s/^${subdomain}\.//" \
            >> root_domains.tmp
    done < "$SUBDOMAINS_TO_REMOVE"
    sort -u "$source_results" -o "$source_results"

    # Remove domains already in raw file
    comm -23 "$source_results" "$RAW" > temp
    mv temp "$source_results"

    # Log blacklisted domains
    # log_domains is used instead of filter as the blacklisted domains should
    # not be removed from the results file.
    log_domains "$(comm -12 "$BLACKLIST" "$source_results")" blacklist

    # Remove whitelisted domains excluding blacklisted domains
    # Note whitelist uses regex matching
    whitelisted_count="$(filter \
        "$(grep -Ef "$WHITELIST" "$source_results" \
        | grep -vxFf "$BLACKLIST")" whitelist)"

    # Remove domains with whitelisted TLDs excluding blacklisted domains
    # mawk does not work with this expression so grep is intentionally chosen.
    # The same applies for the invalid check below.
    whitelisted_tld_count="$(filter \
        "$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' "$source_results" \
        | grep -vxFf "$BLACKLIST")" whitelisted_tld --preserve)"

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

    if [[ "$exclude_from_light" == false ]]; then
        # Collate filtered domains from light sources
        cat "$source_results" >> all_retrieved_light_domains.tmp
    fi

    log_domains "$source_results" saved

    log_source

    rm "$source_results"

    if [[ -f "${source_results}.tmp" ]]; then
        # Save entries that are pending manual review for rerun
        mv "${source_results}.tmp" "$source_results"
    fi
}

# Save filtered domains into the raw file.
save_domains() {
    # Create files to avoid not found errors especially when no light sources
    # were used
    touch all_retrieved_domains.tmp all_retrieved_light_domains.tmp

    if [[ -f entries_for_review.tmp ]]; then
        # Print domains requiring manual review
        printf "\n\e[1mEntries requiring manual review:\e[0m\n"
        sed 's/(/(\o033[31m/; s/)/\o033[0m)/' entries_for_review.tmp

        $FUNCTION --send-telegram \
            "Retrieval: entries requiring manual review\n\n$(<entries_for_review.tmp)"

        printf "\nTelegram notification sent.\n"
    fi

    # Return if no new domains to save
    if [[ ! -s all_retrieved_domains.tmp ]]; then
        printf "\n\e[1mNo new domains to add.\e[0m\n"

        [[ "$USE_EXISTING_RESULTS" == true ]] && return

        $FUNCTION --send-telegram \
            "Retrieval: no new domains added"

        return
    fi

    local count_before count_after count_added

    count_before="$(wc -l < "$RAW")"

    # Save domains to raw files
    sort -u all_retrieved_domains.tmp "$RAW" -o "$RAW"
    sort -u all_retrieved_light_domains.tmp "$RAW_LIGHT" -o "$RAW_LIGHT"

    count_after="$(wc -l < "$RAW")"
    count_added="$(( count_after - count_before ))"

    printf "\nAdded new domains to raw file.\nBefore: %s  Added: %s  After: %s\n" \
        "$count_before" "$count_added" "$count_after"

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    $FUNCTION --send-telegram \
        "Retrieval: added ${count_added} domains"
}

# Save filtered subdomains and root domains into the subdomains and root
# domains files.
save_subdomains() {
    [[ ! -f root_domains.tmp ]] && return

    sort -u root_domains.tmp -o root_domains.tmp

    # Keep subdomains and remove root domains from entries requiring manual
    # review in data/pending
    local entries
    for entries in data/pending/*.tmp; do
        [[ ! -f "$entries" ]] && continue

        # Add back subdomains
        grep -f "$entries" subdomains.tmp | sort -u - "$entries" -o "$entries"

        # Keep only domains not found in root_domains.tmp
        comm -23 "$entries" root_domains.tmp > temp
        mv temp "$entries"
    done

    # Keep only root domains present in the final filtered domains
    comm -12 root_domains.tmp <(sort all_retrieved_domains.tmp) > temp
    mv temp root_domains.tmp

    # Collate filtered root domains
    sort -u root_domains.tmp "$ROOT_DOMAINS" -o "$ROOT_DOMAINS"

    # Collate filtered subdomains
    grep -f root_domains.tmp subdomains.tmp \
        | sort -u - "$SUBDOMAINS" -o "$SUBDOMAINS"
}

# Print and log statistics for each source.
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
# Input:
#   $1: domains to log either in a file or variable
#   $2: event type (dead, whitelisted, etc.)
log_domains() {
    $FUNCTION --log-domains "$1" "$2" "$source_name"
}

# Print error message and exit.
# Input:
#   $1: error message to print
error() {
    printf "\n\e[1;31m%s\e[0m\n\n" "$1" >&2
    exit 1
}

cleanup() {
    # Delete pending directory if no domains to be saved for rerun
    find data/pending -type d -empty -delete

    rm ./*.tmp temp 2> /dev/null || true
}

# The 'source_<source>' functions retrieve results from the respective sources
# and outputs them to source_results.tmp.
# Input:
#   $source_name:          name of the source to use in the console and logs
#   $exclude_from_light:    if true, the results are not included in the light
#                          version (default is false)
#   $USE_EXISTING_RESULTS: if true, skip the retrieval process and use the
#                          existing results files
# Output:
#   source_results.tmp (if USE_EXISTING_RESULTS is false)
#
# Note the output results can be in URL form without subfolders.

source_google_search() {
    # Last checked: 21/01/25
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

    # Loop through search terms
    csvgrep -c 2 -m 'y' -i "$SEARCH_TERMS" | csvcut -c 1 | tail -n +2 \
        | while read -r search_term; do

        # Stop if rate limited
        if [[ "$rate_limited" == true ]]; then
            printf "\n\e[1;31mBoth Google Search API keys are rate limited.\e[0m\n"
            return
        fi
        search_google "$search_term"
    done
}

search_google() {
    # Last checked: 21/01/25
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
    local start params page_results page_domains
    for start in {1..100..10}; do
        # Restrict to results from the last 30 days
        params="cx=${search_id}&key=${search_api_key}&exactTerms=${encoded_search_term}&dateRestrict=m1&sort=date&start=${start}&filter=0"
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
            | mawk -F '/' '{ print $3 }')"
        printf "%s\n" "$page_domains" >> "$source_results"

        # Stop search term if no more pages are required
        (( $(wc -l <<< "$page_domains") < 10 )) && break
    done

    process_source_results
}

source_cybersquatting() {
    # Last checked: 08/02/25
    source_name='Cybersquatting'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    local tlds results

    # Install dnstwist
    command -v dnstwist > /dev/null || pip install -q dnstwist

    # Install URLCrazy and dependencies
    # curl -L required
    curl -sSL 'https://github.com/urbanadventurer/urlcrazy/archive/refs/heads/master.zip' \
        -o urlcrazy.zip
    unzip -q urlcrazy.zip
    command -v ruby > /dev/null || apt-get install -qq ruby ruby-dev
    # sudo is needed for gem
    sudo gem install --silent json colorize async async-dns async-http

    # Get TLDs from the NRD feed for dnstwist.
    # This is not needed for URLCrazy as that already checks for
    # alternate TLDs.
    tlds="$(mawk -F '.' '!seen[$NF]++ { print $NF }' nrd.tmp)"

    # Loop through phishing targets
    mawk -F ',' '$4 == "y" { print $1 }' "$PHISHING_TARGETS" \
        | while read -r target; do

        # Run dnstwist
        results="$(dnstwist "${target}.com" -f list)"

        # Append possible TLDs
        while read -r tld; do
            printf "%s\n" "$results" | mawk -v tld="$tld" '
                { sub(/\.com$/, "."tld); print }' >> results.tmp
        done <<< "$tlds"

        # Run URLCrazy (bash does not work)
        # Note that URLCrazy appends possible TLDs
        ./urlcrazy-master/urlcrazy -r "${target}.com" -f CSV | mawk -F ',' '
            NR > 2 { gsub(/"/, "", $2); print $2 }' >> results.tmp

        sort -u results.tmp -o results.tmp

        # Get matching NRDs
        comm -12 results.tmp nrd.tmp > temp
        mv temp results.tmp

        # Collate results
        cat results.tmp >> source_results.tmp

        # Update counts for the target
        mawk -F ',' \
            -v target="$target" -v results_count="$(wc -l < results.tmp)" '
            BEGIN {OFS = ","}
            $1 == target {
                $2 += results_count
                $3 += 1
            }
            { print }
        ' "$PHISHING_TARGETS" > temp
        mv temp "$PHISHING_TARGETS"

        # Reset results file for the next target domain
        rm results.tmp
    done

    rm -r urlcrazy*
}

source_dga_detector() {
    # Last checked: 14/02/25
    source_name='DGA Detector'
    source_url='https://github.com/exp0se/dga_detector/archive/refs/heads/master.zip'
    exclude_from_light=true

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    # Install DGA Detector and dependencies
    # curl -L required
    curl -sSL "$source_url" -o dga_detector.zip
    unzip -q dga_detector.zip
    pip install -q tldextract

    # Keep only non punycode NRDs with 12 or more characters
    mawk 'length($0) >= 12 && $0 !~ /xn--/' nrd.tmp > domains.tmp

    cd dga_detector-master

    # Set detection threshold. DGA domains fall below the threshold set here.
    # A lower threshold lowers the domain yield and reduces false positives.
    # Note that adding domains to big.txt does not seem to affect detection.
    sed -i "s/threshold = model_data\['thresh'\]/threshold = 0.0009/" \
        dga_detector.py

    # Run DGA Detector on remaining NRDs
    python3 dga_detector.py -f ../domains.tmp > /dev/null

    # Extract DGA domains from json output
    jq -r 'select(.is_dga == true) | .domain' dga_domains.json \
        > ../source_results.tmp

    cd ..

    rm -r dga_detector* domains.tmp
}

source_regex() {
    # Last checked: 08/02/25
    source_name='Regex'
    exclude_from_light=true

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    local pattern

    # Loop through phishing targets
    mawk -F ',' '$8 == "y" { print $1 }' "$PHISHING_TARGETS" \
        | while read -r target; do

        # Get regex of target
        pattern="$(mawk -F ',' -v target="$target" '
            $1 == target { print $5 }' "$PHISHING_TARGETS")"
        local escaped_target="${target//[.]/\\.}"
        local regex="${pattern//&/${escaped_target}}"

        # Get matches in NRD feed and update counts
        # awk is used here instead of mawk for compatibility with the regex
        # expressions.
        mawk -F ',' -v target="$target" -v results="$(
            awk "/${regex}/" nrd.tmp \
                | sort -u \
                | tee -a source_results.tmp \
                | wc -l
            )" '
            BEGIN {OFS = ","}
            $1 == target {
                $6 += results
                $7 += 1
            }
            { print }
        ' "$PHISHING_TARGETS" > temp
        mv temp "$PHISHING_TARGETS"
    done
}

source_165antifraud() {
    # Last checked: 17/02/25
    # Credit to @tanmarpn for the source idea
    source_name='165 Anti-fraud'
    source_url='https://165.npa.gov.tw/api/article/subclass/3'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSL "$source_url" \
        | jq --arg year "$(date +%Y)" '.[] | select(.publishDate | contains($year)) | .content' \
        | grep -Po "\\\">(https?://)?\K${DOMAIN_REGEX}" > source_results.tmp
}

source_aa419() {
    # Last checked: 23/12/24
    source_name='Artists Against 419'
    source_url='https://api.aa419.org/fakesites'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    # Trailing slash intentionally omitted
    curl -sSH "Auth-API-Id:${AA419_API_ID}" \
        "${source_url}/0/250?Status=active" --retry 2 --retry-all-errors \
        | jq -r '.[].Domain' > source_results.tmp
}

source_behindmlm() {
    # Last checked: 17/02/25
    source_name='BehindMLM'
    source_url='https://behindmlm.com'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSLZ --retry 2 --retry-all-errors "${source_url}/page/[1-15]" \
        | grep -iPo "&#8220;\K${DOMAIN_REGEX}(?=&#8221;)|<li>\K${DOMAIN_REGEX}|(;|:) \K${DOMAIN_REGEX}|and \K${DOMAIN_REGEX}" \
        > source_results.tmp
}

source_bugsfighter() {
    # Last checked: 17/02/25
    source_name='BugsFighter'
    source_url='https://www.bugsfighter.com/blog'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSLZ --retry 2 --retry-all-errors "${source_url}/page/[1-15]" \
        | grep -iPo "remove \K${DOMAIN_REGEX}" > source_results.tmp
}

source_coi.gov.cz() {
    # Last checked: 17/02/25
    source_name='Česká Obchodní Inspekce'
    source_url='https://coi.gov.cz/pro-spotrebitele/rizikove-e-shopy'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSL --retry 2 --retry-all-errors "${source_url}/" \
        | grep -Po "<span>\K${DOMAIN_REGEX}(?=.*</span>)" > source_results.tmp
}

source_crypto_scam_tracker() {
    # Last checked: 12/02/25
    source_name='DFPI Crypto Scam Tracker'
    source_url='https://dfpi.ca.gov/consumers/crypto/crypto-scam-tracker'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSL --retry 2 --retry-all-errors "$source_url" \
        | grep -Po "column-5\">\K(https?)?${DOMAIN_REGEX}" > source_results.tmp
}

source_emerging_threats() {
    # Last checked: 17/02/25
    source_name='Emerging Threats'
    source_url='https://rules.emergingthreats.net/open/suricata-5.0/emerging.rules.zip'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSL --retry 2 --retry-all-errors "$source_url" -o rules.zip
    unzip -q rules.zip -d rules

    # Ignore rules with specific payload keywords. See here:
    # https://docs.suricata.io/en/suricata-6.0.0/rules/payload-keywords.html
    # Note 'endswith' is accepted as those rules tend to be wildcard matches of
    # root domains (leading periods are removed for those rules).
    local RULE
    for RULE in emerging-adware_pup emerging-coinminer emerging-exploit_kit \
        emerging-malware emerging-mobile_malware emerging-phishing; do
        cat "rules/rules/${RULE}.rules"
    done | mawk '/dns[\.|_]query/ &&
        !/^#|content:!|startswith|offset|distance|within|pcre/' \
        | grep -Po "content:\"\.?\K${DOMAIN_REGEX}" > source_results.tmp

    rm -r rules*
}

source_fakewebshoplisthun() {
    # Last checked: 17/02/25
    source_name='FakeWebshopListHUN'
    source_url='https://raw.githubusercontent.com/FakesiteListHUN/FakeWebshopListHUN/refs/heads/main/fakewebshoplist'
    exclude_from_light=true  # Has a few false positives

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSL "$source_url" | grep -Po "^(\|\|)?\K${DOMAIN_REGEX}(?=\^?$)" \
        > source_results.tmp
}

source_jeroengui() {
    # Last checked: 12/02/25
    source_name='Jeroengui'
    source_url='https://file.jeroengui.be'
    exclude_from_light=true  # Too many domains

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    local url_shorterners_whitelist='https://raw.githubusercontent.com/hagezi/dns-blocklists/refs/heads/main/adblock/whitelist-urlshortener.txt'

    # Get domains from various weekly lists and remove link shorterners
    for list in phishing malware scam; do
        curl -sSL "${source_url}/${list}/last_week.txt" \
            | grep -Po "^https?://\K${DOMAIN_REGEX}"
    done | grep -vF \
        "$(curl -sSL "$url_shorterners_whitelist" \
        | grep -Po "\|\K${DOMAIN_REGEX}")" > source_results.tmp

    # Get matching NRDs for the light version. Unicode is only processed by the
    # full version.
    comm -12 <(sort source_results.tmp) nrd.tmp > jeroengui_nrds.tmp
}

source_jeroengui_nrd() {
    # Last checked: 29/12/24
    # For the light version
    # Only includes domains found in the NRD feed
    source_name='Jeroengui (NRDs)'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    mv jeroengui_nrds.tmp source_results.tmp
}

source_greatis() {
    # Last checked: 17/02/25
    source_name='Wildcat Cyber Patrol'
    source_url='https://greatis.com/unhackme/help/category/remove'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSLZ --retry 2 --retry-all-errors "${source_url}/page/[1-15]" \
        | grep -iPo "rel=\"bookmark\">remove \K${DOMAIN_REGEX}" \
        > source_results.tmp
}

source_gridinsoft() {
    # Last checked: 17/02/25
    source_name='Gridinsoft'
    source_url='https://raw.githubusercontent.com/jarelllama/Blocklist-Sources/refs/heads/main/gridinsoft.txt'
    exclude_from_light=true  # Has a few false positives

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSL "$source_url" | grep -Po "\|\K${DOMAIN_REGEX}" \
        > source_results.tmp
}

source_malwareurl() {
    # Last checked: 17/02/25
    source_name='MalwareURL'
    source_url='https://raw.githubusercontent.com/jarelllama/Blocklist-Sources/refs/heads/main/malwareurl.txt'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSL "$source_url" | grep -Po "\|\K${DOMAIN_REGEX}" \
        > source_results.tmp
}

source_manual() {
    source_name='Manual'
}

source_pcrisk() {
    # Last checked: 17/02/25
    source_name='PCrisk'
    source_url='https://www.pcrisk.com/removal-guides'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSLZ --retry 2 --retry-all-errors "${source_url}?start=[0-15]0" \
        | mawk '/<div class="text-article">/ { getline; getline; print }' \
        | grep -Po "${DOMAIN_SQUARE_REGEX}" > source_results.tmp
}

source_phishstats() {
    # Last checked: 17/02/25
    source_name='PhishStats'
    source_url='https://phishstats.info/phish_score.csv'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    # Get URLs with no subdirectories (some of the URLs use docs.google.com)
    curl -sSL "$source_url" | grep -Po "\"https?://\K${DOMAIN_REGEX}(?=/?\")" \
        > source_results.tmp
}

source_puppyscams() {
    # Last checked: 17/02/25
    source_name='PuppyScams.org'
    source_url='https://puppyscams.org'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSLZ --retry 2 --retry-all-errors "${source_url}/?page=[1-15]" \
        | grep -Po " \K${DOMAIN_REGEX}(?=</h4></a>)" > source_results.tmp
}

source_scamadviser() {
    # Last checked: 17/02/25
    source_name='ScamAdviser'
    source_url='https://www.scamadviser.com/articles'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSLZ --retry 2 --retry-all-errors "${source_url}?p=[1-15]" \
        | grep -Po "[A-Z0-9][-.]?${DOMAIN_REGEX}(?= ([A-Z]|a ))" \
        > source_results.tmp
}

source_scamdirectory() {
    # Last checked: 17/02/25
    source_name='Scam Directory'
    source_url='https://scam.directory/category'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    # head -n causes grep broken pipe error
    curl -sSL --retry 2 --retry-all-errors "${source_url}/" \
        | grep -Po "<span>\K${DOMAIN_REGEX}(?=<br>)" > source_results.tmp
}

source_scamminder() {
    # Last checked: 18/02/25
    source_name='ScamMinder'
    source_url='https://scamminder.com/websites'
    exclude_from_light=true

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSLZ --retry 2 --retry-all-errors "${source_url}/page/[1-100]" \
        | mawk '/Trust Score :  strongly low/ { getline; print }' \
        | grep -Po "class=\"h5\">\K${DOMAIN_REGEX}" > source_results.tmp
}

source_unit42() {
    # Last checked: 17/02/25
    source_name='Unit42'
    source_url='https://github.com/PaloAltoNetworks/Unit42-timely-threat-intel/archive/refs/heads/main.zip'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSL "$source_url" -o unit42.zip
    unzip -q unit42.zip -d unit42

    grep -hPo "hxxps?\[:\]//\K${DOMAIN_SQUARE_REGEX}|^- \K${DOMAIN_SQUARE_REGEX}" \
        unit42/*/"$(date +%Y)"* > source_results.tmp

    rm -r unit42*
}

source_viriback_tracker() {
    # Last checked: 17/02/25
    source_name='ViriBack C2 Tracker'
    source_url='https://tracker.viriback.com/dump.php'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSL "$source_url" | mawk -v year="$(date +"%Y")" \
        -F ',' '$4 ~ year { print $2 }' \
        | grep -Po "^https?://\K${DOMAIN_REGEX}" > source_results.tmp
}

source_vzhh() {
    # Last checked: 17/02/25
    source_name='Verbraucherzentrale Hamburg'
    source_url='https://www.vzhh.de/themen/einkauf-reise-freizeit/einkauf-online-shopping/fake-shop-liste-wenn-guenstig-richtig-teuer-wird'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSL --retry 2 --retry-all-errors "$source_url" \
        | grep -Po "field--item\">\K${DOMAIN_REGEX}(?=</div>)" \
        > source_results.tmp
}

source_wipersoft() {
    # Last checked: 17/02/25
    source_name='WiperSoft'
    source_url='https://www.wipersoft.com/blog'

    [[ "$USE_EXISTING_RESULTS" == true ]] && return

    curl -sSLZ --retry 2 --retry-all-errors "${source_url}/page/[1-15]" \
        | mawk '/<div class="post-content">/ { getline; print }' \
        | grep -Po "${DOMAIN_REGEX}" > source_results.tmp
}

# Entry point

set -e

trap cleanup EXIT

$FUNCTION --format-all

main

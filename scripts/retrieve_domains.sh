#!/bin/bash

# Retrieve domains from the sources, process them, and output a raw file
# that contains the cumulative domains from all sources over time.

readonly FUNCTION='bash scripts/tools.sh'
readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly PHISHING_TARGETS='config/phishing_detection.csv'
readonly REVIEW_CONFIG='config/review_config.csv'
readonly SEARCH_TERMS='config/search_terms.csv'
readonly SOURCES='config/sources.csv'
readonly SOURCE_LOG='config/source_log.csv'
# '[\p{L}\p{N}][\p{L}\p{N}-]*[\p{L}\p{N}]' matches the root domain and subdomains
# '[\p{L}\p{N}]' matches single character subdomains
# '[\p{L}}][\p{L}\p{N}-]*[\p{L}\p{N}]' matches the TLD (TLDs can not start with a number)
readonly DOMAIN_REGEX='(?:([\p{L}\p{N}][\p{L}\p{N}-]*[\p{L}\p{N}]|[\p{L}\p{N}])\.)+[\p{L}}][\p{L}\p{N}-]*[\p{L}\p{N}]'
# '\[?\.\]?' matches periods optionally enclosed by square brackets
readonly DOMAIN_SQUARE_REGEX='(?:([\p{L}\p{N}][\p{L}\p{N}-]*[\p{L}\p{N}]|[\p{L}\p{N}])\[?\.\]?)+[\p{L}}][\p{L}\p{N}-]*[\p{L}\p{N}]'

main() {
    if [[ -d data/pending ]]; then
        # Use existing results in the pending directory
        readonly USE_EXISTING_RESULTS=true
        printf "\nUsing existing lists of retrieved results.\n"
    else
        readonly USE_EXISTING_RESULTS=false
        mkdir -p data/pending

        # Install jq
        command -v jq > /dev/null || apt-get install -qq jq

        $FUNCTION --download-nrd-feed

        # Remove already processed NRDs to save processing time
        comm -23 nrd.tmp <(sort "$RAW" "$DEAD_DOMAINS" "$PARKED_DOMAINS") \
            > temp
        mv temp nrd.tmp
    fi

    # Install idn2 here instead of in $FUNCTION to not bias source processing
    # time.
    command -v idn2 > /dev/null || sudo apt-get install idn2 > /dev/null

    $FUNCTION --download-toplist

    $FUNCTION --update-review-config

    # Store whitelist and blacklist as a regex expression
    whitelist="$($FUNCTION --get-whitelist)"
    blacklist="$($FUNCTION --get-blacklist)"
    readonly whitelist blacklist

    retrieve_source_results

    save_domains
}

# Run each source function to retrieve results which are then processed per
# source by process_source_results().
retrieve_source_results() {
    local source_results source_function execution_time

    # Loop through enabled sources
    # The while loop sets source_name as local
    while read -r source_name; do
        # Initialize source variables
        local source_url=''
        local rate_limited=false
        local too_large=false
        local query_count=''

        source_results="data/pending/${source_name// /_}.tmp"

        # If using existing results, skip sources with no results to process.
        # The Google Search source is an exception as each search term has its
        # own results file.
        if [[ "$USE_EXISTING_RESULTS" == true \
            && ! -f "$source_results" \
            && "$source_name" != 'Google Search' ]]; then
            continue
        fi

        # Run the Manual source
        if [[ "$source_name" == 'Manual' ]]; then
            printf "\n\e[1mSource: Manual\e[0m\n"
            execution_time="$(date +%s)"
            process_source_results
            continue
        fi

        source_function="$(mawk -v source="$source_name" -F ',' '
            $1 == source { print $2 }' "$SOURCES")"

        # The Google Search source handles its own processing
        if [[ "$source_name" == 'Google Search' ]]; then
            $source_function || true
            continue
        fi

        printf "\n\e[1mSource: %s\e[0m\n" "$source_name"

        execution_time="$(date +%s)"

        # Process existing results if present
        if [[ "$USE_EXISTING_RESULTS" == true ]]; then
            process_source_results
            continue
        fi

        # Run source to retrieve new results
        $source_function || true

        # Error if the source did not create its source results file
        if [[ ! -f "$source_results" ]]; then
            printf "\e[1;31mSource results file not found.\e[0m\n"
            # Create source results file to ensure proper logging
            touch "$source_results"
        fi

        process_source_results

    done <<< "$({
            printf 'Manual,,,y\n'
            mawk -F ',' '$1 != "Google Search" { print }' "$SOURCES"
            mawk -F ',' '$1 == "Google Search" { print }' "$SOURCES"
        } | mawk -F ',' '$4 == "y" { print $1 }')"
        # Run the Manual source first and the Google Search source last
}

# Called by process_source_results() to remove entries from the source results
# file and to log the entries into the domain log.
# Input:
#   $1: entries to process passed in a variable
#   $2: tag to be shown in the domain log
#     --no-log:    do not log entries into the domain log
#     --preserve:  save entries for manual review and for rerun
# Output:
#   Number of entries that were passed
filter() {
    local entries="$1"
    local tag="$2"

    # Return with 0 entries if no entries found
    if [[ -z "$entries" ]]; then
        printf 0
        return
    fi

    # Remove entries from the results file
    comm -23 "$source_results" <(printf "%s" "$entries") > temp
    mv temp "$source_results"

    if [[ "$3" != '--no-log' ]]; then
       $FUNCTION --log-domains "$entries" "$tag" "$source_name"
    fi

    if [[ "$3" == '--preserve' ]]; then
        # Save entries for console output
        mawk -v tag="$tag" '{ print $0 " (" tag ")" }' <<< "$entries" \
            >> entries_for_review.tmp

        # Save entries into the review config file
        mawk -v source="$source_name" -v reason="$tag" '
            { print source "," $0 "," reason ",," }' <<< "$entries" \
            >> "$REVIEW_CONFIG"

        # Remove duplicates from the review config file
        mawk '!seen[$0]++' "$REVIEW_CONFIG" > temp
        mv temp "$REVIEW_CONFIG"

        # Save entries to use in rerun
        printf "%s\n" "$entries" >> "${source_results}.tmp"
    fi

    # Return the number of entries
    wc -l <<< "$entries"
}

# Process and filter the results from the source, append the resulting domains
# to all_retrieved_domains.tmp/all_retrieved_light_domains.tmp, and save
# entries requiring manual review.
process_source_results() {
    local raw_count dead_count parked_count whitelisted_count
    local whitelisted_tld_count in_toplist_count filtered_count

    # Count the number of unfiltered domains
    raw_count="$(wc -l < "$source_results")"

    # Convert URLs to domains, remove square brackets, and convert to
    # lowercase. This is done here once instead of multiple times in the source
    # functions. Note that this still allows invalid entries like entries with
    # subfolders to get through so they can be flagged later on.
    mawk '{
        gsub(/https?:\/\//, "")
        gsub(/[\[\]]/, "")
        print tolower($0)
    }' "$source_results" | sort -u -o "$source_results"

    # Remove non-domain entries
    # Redirect output to /dev/null as the invalid entries count is not needed
    filter "$(grep -vP "^${DOMAIN_REGEX}$" "$source_results")" \
        invalid --preserve > /dev/null

    # Convert Unicode to Punycode
    $FUNCTION --convert-unicode "$source_results"

    # Remove known dead domains (dead domains file is not sorted)
    dead_count="$(filter \
        "$(comm -12 <(sort "$DEAD_DOMAINS") "$source_results")" \
        dead --no-log)"

    # Remove known parked domains (parked domains file is not sorted)
    parked_count="$(filter \
        "$(comm -12 <(sort "$PARKED_DOMAINS") "$source_results")" \
        parked --no-log)"

    # Remove domains already in the raw file
    comm -23 "$source_results" "$RAW" > temp
    mv temp "$source_results"

    # Error when a source retrieves an unusually large amount of results
    if (( $(wc -l < "$source_results") > 10000 )); then
        too_large=true
        # Save entries for troubleshooting
        cp "$source_results" "${source_results}.tmp"
        # Empty source results to ensure proper logging
        : > "$source_results"
    fi

    # Log blacklisted domains
    # 'filter' is not used as the blacklisted domains should not be removed
    # from the results file.
    $FUNCTION --log-domains "$(mawk -v blacklist="$blacklist" '
        $0 ~ blacklist' "$source_results")" blacklist "$source_name"

    # Remove whitelisted domains excluding blacklisted domains
    # awk is used here instead of mawk for compatibility with the regex
    # expression.
    whitelisted_count="$(filter \
        "$(awk -v whitelist="$whitelist" -v blacklist="$blacklist" '
        $0 ~ whitelist && $0 !~ blacklist' "$source_results")" whitelist)"

    # Remove domains with whitelisted TLDs excluding blacklisted domains
    # awk is used here instead of mawk for compatibility with the regex
    # expression.
    whitelisted_tld_count="$(filter \
        "$(awk -v blacklist="$blacklist" '
        /\.(gov|edu|mil)(\.[a-z]{2})?$/ && $0 !~ blacklist
        ' "$source_results")" whitelisted_tld --preserve)"

    # Remove domains found in the toplist excluding blacklisted domains
    in_toplist_count="$(filter \
        "$(mawk -v blacklist="$blacklist" '
        NR==FNR { lines[$0]; next } $0 in lines && $0 !~ blacklist
        ' "$source_results" toplist.tmp)" toplist --preserve)"

    # Count the number of filtered domains
    filtered_count="$(wc -l < "$source_results")"

    # Collate filtered domains
    cat "$source_results" >> all_retrieved_domains.tmp

    if [[ -z "$(mawk -v source="$source_name" -F ',' '
        $1 == source { print $3 }' "$SOURCES")" ]]; then
        # Collate filtered domains from light sources
        cat "$source_results" >> all_retrieved_light_domains.tmp
    fi

    $FUNCTION --log-domains "$source_results" saved "$source_name"

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

# Print and log statistics for each source.
log_source() {
    local total_whitelisted_count excluded_count
    local status='saved'

    # Check for errors to log
    if [[ "$rate_limited" == true ]]; then
        status='ERROR: rate_limited'
    elif [[ "$too_large" == true ]]; then
        status='ERROR: too_large'
    elif (( raw_count == 0 )); then
        status='ERROR: empty'
    fi

    total_whitelisted_count="$(( whitelisted_count + whitelisted_tld_count ))"
    excluded_count="$(( dead_count + parked_count ))"

    if [[ -n "$search_term" ]]; then
        search_term="\"${search_term:0:100}...\""
    fi

    echo "$(TZ=Asia/Singapore date +"%H:%M:%S %d-%m-%y"),${source_name},\
${search_term},${raw_count},${filtered_count},${total_whitelisted_count},\
${dead_count},${parked_count},${in_toplist_count},${query_count},${status}" \
    >> "$SOURCE_LOG"

    [[ "$rate_limited" == true ]] && return

    if [[ "$status" == 'ERROR: empty' ]]; then
        printf "\e[1;31mNo results retrieved. Potential error occurred.\e[0m\n"

        $FUNCTION --send-telegram \
            "Warning: '$source_name' retrieved no results. Potential error occurred."

    elif [[ "$status" == 'ERROR: too_large' ]]; then
        printf "\e[1;31mSource is unusually large (%s entries). Not saving.\e[0m\n" \
            "$(wc -l < "${source_results}.tmp")"

        $FUNCTION --send-telegram \
            "Warning: '$source_name' is unusually large ($(wc -l < "${source_results}.tmp") entries). Potential error occurred."

    else
        printf "Raw:%4s  Final:%4s  Whitelisted:%4s  Excluded:%4s  Toplist:%4s\n" \
            "$raw_count" "$filtered_count" "$total_whitelisted_count" \
            "$excluded_count" "$in_toplist_count"
    fi

    printf "Processing time: %s seconds\n" "$(( $(date +%s) - execution_time ))"
    printf -- "----------------------------------------------------------------------\n"
}

cleanup() {
    # Delete pending directory if no domains to be saved for rerun
    find data/pending -type d -empty -delete

    rm ./*.tmp temp 2> /dev/null || true
}

# The 'source_<source>' functions retrieve results from the respective sources
# and output them to $source_results.

source_google_search() {
    # Last checked: 05/03/25
    source_url='https://customsearch.googleapis.com/customsearch/v1'
    local search_id="$GOOGLE_SEARCH_ID"
    local search_api_key="$GOOGLE_SEARCH_API_KEY"
    local search_term encoded_search_term start page_results

    # Check for existing results
    if [[ "$USE_EXISTING_RESULTS" == true ]]; then
        # Loop through the results from each search term
        for source_results in data/pending/google_search_*.tmp; do
            [[ ! -f "$source_results" ]] && return

            # Remove header from file name
            search_term="${source_results#data/pending/google_search_}"
            # Remove file extension from file name to get search term
            search_term="${search_term%.tmp}"

            printf "\n\e[1mSource: Google Search\e[0m\n"
            printf "Search term: \"%s...\"\n" "${search_term:0:100}"

            # Set execution time for each individual search term
            execution_time="$(date +%s)"

            process_source_results
        done
        return
    fi

    # Install csvkit
    command -v csvgrep > /dev/null || pip install -q csvkit

    # Loop through search terms
    while read -r search_term; do
        # Stop if rate limited
        if [[ "$rate_limited" == true ]]; then
            printf "\e[1;31mBoth Google Search API keys are rate limited.\e[0m\n"
            return
        fi

        # Remove quotes before encoding
        search_term="${search_term//\"/}"
        # Replace non-alphanumeric characters with spaces
        encoded_search_term="${search_term//[^[:alnum:]]/%20}"
        query_count=0

        # Assign and create results file to ensure proper logging
        search_term="${search_term//\//}"  # Remove slashes
        source_results="data/pending/google_search_${search_term:0:100}.tmp"
        touch "$source_results"

        printf "\n\e[1mSource: Google Search\e[0m\n"
        printf "Search term: \"%s...\"\n" "${search_term:0:100}"

        # Set execution time for each individual search term
        execution_time="$(date +%s)"

        # Loop through each page of results
        for start in {1..100..10}; do
            # Restrict to results from the last 30 days
            page_results="$(
                curl -sS \
                "${source_url}?cx=${search_id}&key=${search_api_key}&exactTerms=${encoded_search_term}&dateRestrict=m1&sort=date&start=${start}&filter=0"
            )"

            (( query_count++ ))

            # Use next API key if first key is rate limited
            if [[ "$page_results" == *rateLimitExceeded* ]]; then
                # Stop all searches if second key is also rate limited
                if [[ "$search_id" == "$GOOGLE_SEARCH_ID_2" ]]; then
                    rate_limited=true
                    break
                fi

                printf "\e[1;31mGoogle Search rate limited. Switching API keys.\e[0m\n"

                # Switch API keys
                readonly search_api_key="$GOOGLE_SEARCH_API_KEY_2"
                readonly search_id="$GOOGLE_SEARCH_ID_2"

                # Continue to next page (skip current rate limited page)
                continue
            fi

            # Stop search term if page has no results
            jq -e '.items' &> /dev/null <<< "$page_results" || break

            # Save domains from each page and stop search term if no more pages
            # are required
            if [[ "$(jq -r '.items[].link' <<< "$page_results" \
                | mawk -F '/' '{ print $3 }' \
                | tee -a "$source_results" \
                | wc -l)" -lt 10 ]]; then
                break
            fi
        done

        process_source_results

    done <<< "$(
        csvgrep -c 2 -m 'y' -i "$SEARCH_TERMS" | csvcut -c 1 | tail -n +2)"
}

source_dga_detector() {
    # Last checked: 04/03/25
    source_url='https://github.com/jarelllama/dga_detector/archive/refs/heads/master.zip'

    # Install DGA Detector and dependencies
    curl -sSL --retry 2 --retry-all-errors "$source_url" -o dga_detector.zip
    unzip -q dga_detector.zip
    pip install -q tldextract

    # Keep only non-Punycode NRDs with 12 or more characters
    mawk 'length($0) >= 12 && !/xn--/' nrd.tmp > domains.tmp

    cd dga_detector-master

    # Set detection threshold. DGA domains fall below the threshold set here.
    # A lower threshold lowers the domain yield and reduces false positives.
    sed -i "s/threshold = model_data\['thresh'\]/threshold = 0.0008/" \
        dga_detector.py

    # Run DGA Detector on remaining NRDs
    python3 dga_detector.py -f ../domains.tmp > /dev/null

    # Extract DGA domains from JSON output
    jq -r 'select(.is_dga == true) | .domain' dga_domains.json \
        > "../${source_results}"

    cd ..

    rm -r dga_detector* domains.tmp
}

source_dnstwist() {
    # Last checked: 04/03/25
    local tlds

    command -v dnstwist > /dev/null || pip install -q dnstwist

    # Get TLDs from the NRD feed
    tlds="$(mawk -F '.' '!seen[$NF]++ { print $NF }' nrd.tmp)"

    # Loop through phishing targets
    mawk -F ',' '$4 == "y" { print $1 }' "$PHISHING_TARGETS" \
        | while read -r target; do

        # Run dnstwist and append TLDs
        # Note that redirecting the output to a file is faster than piping.
        mawk -v tlds="$tlds" '{
            sub(/\.com$/, "")
            n = split(tlds, tldArray, " ")
            for (i = 1; i <= n; i++) {
                print $0"."tldArray[i]
            }
        }' <<< "$(dnstwist "${target}.com" -f list)" > results.tmp

        # Get matching NRDs
        comm -12 <(sort -u results.tmp) nrd.tmp > temp
        mv temp results.tmp

        # Collate results
        cat results.tmp >> "$source_results"

        # Update counts for the target
        mawk -v target="$target" \
            -v results_count="$(wc -l < results.tmp)" -F ',' '
            BEGIN { OFS = "," }
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
}

source_regex() {
    # Last checked: 03/03/25
    local pattern

    # Loop through phishing targets
    mawk -F ',' '$8 == "y" { print $1 }' "$PHISHING_TARGETS" \
        | while read -r target; do

        # Get regex of target
        pattern="$(mawk -v target="$target" -F ',' '
            $1 == target { print $5 }' "$PHISHING_TARGETS")"
        local escaped_target="${target//[.]/\\.}"
        local regex="${pattern//&/${escaped_target}}"

        # Get matches in NRD feed and update counts
        # awk is used here instead of mawk for compatibility with the regex
        # expressions.
        mawk -v target="$target" -v results="$(
            awk "/${regex}/" nrd.tmp \
                | sort -u \
                | tee -a "$source_results" \
                | wc -l
            )" -F ',' '
            BEGIN { OFS = "," }
            $1 == target {
                $6 += results
                $7 += 1
            }
            { print }
        ' "$PHISHING_TARGETS" > temp
        mv temp "$PHISHING_TARGETS"
    done
}

source_urlcrazy() {
    # Last checked: 04/03/25
    source_url='https://github.com/urbanadventurer/urlcrazy/archive/refs/heads/master.zip'

    # Install URLCrazy and dependencies
    curl -sSL --retry 2 --retry-all-errors "$source_url" -o urlcrazy.zip
    unzip -q urlcrazy.zip
    command -v ruby > /dev/null || apt-get install -qq ruby ruby-dev
    # sudo is needed for gem
    sudo gem install --silent json colorize async async-dns async-http

    # Loop through phishing targets
    mawk -F ',' '$4 == "y" { print $1 }' "$PHISHING_TARGETS" \
        | while read -r target; do

        # Run URLCrazy (bash does not work)
        # Note that URLCrazy appends possible TLDs
        ./urlcrazy-master/urlcrazy -r "${target}.com" -f CSV | mawk -F ',' '
        NR > 2 { gsub(/"/, "", $2); print $2 }' > results.tmp

        # Get matching NRDs
        comm -12 <(sort -u results.tmp) nrd.tmp > temp
        mv temp results.tmp

        # Collate results
        cat results.tmp >> "$source_results"

        # Update counts for the target
        mawk -v target="$target" -v results_count="$(wc -l < results.tmp)" \
            -F ',' '
            BEGIN { OFS = "," }
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

source_165antifraud() {
    # Last checked: 17/02/25
    # Credit to @tanmarpn for the source idea
    source_url='https://165.npa.gov.tw/api/article/subclass/3'

    curl -sSL --retry 2 --retry-all-errors "$source_url" \
        | jq --arg year "$(date +%Y)" '.[] | select(.publishDate | contains($year)) | .content' \
        | grep -Po "\\\">(https?://)?\K${DOMAIN_REGEX}" > "$source_results"
}

source_aa419() {
    # Last checked: 10/03/25
    source_url='https://api.aa419.org/fakesites'

    # Trailing slash intentionally omitted
    curl -sS --retry 2 --retry-all-errors -H "Auth-API-Id:${AA419_API_ID}" \
        "${source_url}/0/250?Status=active" --retry 2 --retry-all-errors \
        | jq -r '.[].Domain' > "$source_results"
}

source_behindmlm() {
    # Last checked: 10/03/25
    source_url='https://behindmlm.com'

    curl -sSLZ --retry 2 --retry-all-errors "${source_url}/page/[1-15]" \
        | grep -iPo "&#8220;\K${DOMAIN_REGEX}(?=&#8221;)|<li>\K${DOMAIN_REGEX}|(;|:) \K${DOMAIN_REGEX}|and \K${DOMAIN_REGEX}" \
        > "$source_results"
}

source_bugsfighter() {
    # Last checked: 10/03/25
    source_url='https://www.bugsfighter.com/blog'

    curl -sSLZ --retry 2 --retry-all-errors "${source_url}/page/[1-15]" \
        | grep -iPo "remove \K${DOMAIN_REGEX}" > "$source_results"
}

source_chainabuse() {
    # Last checked: 03/03/25
    source_url='https://raw.githubusercontent.com/jarelllama/Blocklist-Sources/refs/heads/main/chainabuse.txt'

    curl -sSL --retry 2 --retry-all-errors "$source_url" -o "$source_results"
}

source_coi.gov.cz() {
    # Last checked: 10/03/25
    source_url='https://coi.gov.cz/pro-spotrebitele/rizikove-e-shopy'

    curl -sSL --retry 2 --retry-all-errors "$source_url" \
        | mawk '/<p class = "list_titles">/ { getline; getline; print }' \
        | grep -Po "<span>\K$DOMAIN_REGEX" > "$source_results"
}

source_crypto_scam_tracker() {
    # Last checked: 15/03/25
    source_url='https://dfpi.ca.gov/consumers/crypto/crypto-scam-tracker'

    curl -sSL --retry 2 --retry-all-errors "$source_url" | mawk '
        /"column-4"/ && /"column-5"/ {
            sub(/.*column-4">/, "")
            sub(/<\/th><th class="column-5">.*/, "")
            print
            next
        }
        /"column-4"/ {
            block = 1;
            next
        }
        /"column-5"/ {
            block = 0
        }
        block
        ' | grep -Po "(https?://)?\K${DOMAIN_REGEX}" > "$source_results"
}

source_emerging_threats() {
    # Last checked: 17/02/25
    source_url='https://rules.emergingthreats.net/open/suricata-5.0/emerging.rules.zip'

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
        | grep -Po "content:\"\.?\K${DOMAIN_REGEX}" > "$source_results"

    rm -r rules*
}

source_fakewebshoplisthun() {
    # Last checked: 17/02/25
    source_url='https://raw.githubusercontent.com/FakesiteListHUN/FakeWebshopListHUN/refs/heads/main/fakewebshoplist'

    curl -sSL --retry 2 --retry-all-errors "$source_url" \
        | grep -Po "^(\|\|)?\K${DOMAIN_REGEX}(?=\^?$)" > "$source_results"
}

source_greatis() {
    # Last checked: 10/03/25
    source_url='https://greatis.com/unhackme/help/category/remove'

    curl -sSLZ --retry 2 --retry-all-errors "${source_url}/page/[1-15]" \
        | grep -iPo "rel=\"bookmark\">remove \K${DOMAIN_REGEX}" \
        > "$source_results"
}

source_gridinsoft() {
    # Last checked: 17/02/25
    source_url='https://raw.githubusercontent.com/jarelllama/Blocklist-Sources/refs/heads/main/gridinsoft.txt'

    curl -sSL --retry 2 --retry-all-errors "$source_url" -o "$source_results"
}

source_jeroengui() {
    # Last checked: 03/03/25
    local url_shorterners

    source_url='https://file.jeroengui.be'
    url_shorterners='https://raw.githubusercontent.com/hagezi/dns-blocklists/refs/heads/main/adblock/whitelist-urlshortener.txt'

    # Get domains from various weekly lists and exclude link shorteners
    curl -sSLZ --retry 2 --retry-all-errors \
        "${source_url}/phishing/last_week.txt" \
        "${source_url}/malware/last_week.txt" \
        "${source_url}/scam/last_week.txt" \
        | grep -Po "^https?://\K${DOMAIN_REGEX}" \
        | grep -vF "$(curl -sSL --retry 2 --retry-all-errors "$url_shorterners" \
        | grep -Po "\|\K${DOMAIN_REGEX}")" > "$source_results"

    # Get matching NRDs for the light version. Unicode is only processed by the
    # full version.
    comm -12 <(sort "$source_results") nrd.tmp > jeroengui_nrds.tmp
}

source_jeroengui_nrd() {
    # Last checked: 29/12/24
    # Only includes domains found in the NRD feed for the light version
    mv jeroengui_nrds.tmp "$source_results"
}

source_malwarebytes() {
    # Last checked: 06/03/25
    source_url='https://www.malwarebytes.com/blog/detections'

    curl -sSL --retry 2 --retry-all-errors "$source_url" \
        | grep -Po ">\K${DOMAIN_REGEX}(?=</a>)" | mawk '!/[A-Z]/' \
        > "$source_results"
}

source_malwareurl() {
    # Last checked: 17/02/25
    source_url='https://raw.githubusercontent.com/jarelllama/Blocklist-Sources/refs/heads/main/malwareurl.txt'

    curl -sSL --retry 2 --retry-all-errors "$source_url" -o "$source_results"
}

source_pcrisk() {
    # Last checked: 09/03/25
    source_url='https://www.pcrisk.com/removal-guides'

    curl -sSLZ --retry 2 --retry-all-errors "${source_url}?start=[0-15]0" \
        | mawk '/<div class="text-article">/ { getline; getline; print }' \
        | grep -Po "${DOMAIN_SQUARE_REGEX}" > "$source_results"
}

source_phishstats() {
    # Last checked: 17/02/25
    source_url='https://phishstats.info/phish_score.csv'

    # Get URLs with no subdirectories (some of the URLs use docs.google.com)
    curl -sSL --retry 2 --retry-all-errors "$source_url" \
        | grep -Po "\"https?://\K${DOMAIN_REGEX}(?=/?\")" > "$source_results"
}

source_puppyscams() {
    # Last checked: 17/02/25
    source_url='https://puppyscams.org'

    curl -sSLZ --retry 2 --retry-all-errors "${source_url}/?page=[1-15]" \
        | grep -Po " \K${DOMAIN_REGEX}(?=</h4></a>)" > "$source_results"
}

source_safelyweb() {
    # Last checked: 02/03/25
    source_url='https://safelyweb.com/scams-database'

    curl -sSLZ --retry 2 --retry-all-errors "${source_url}/?per_page=[1-30]" \
        | grep -iPo "suspicious website</div> <h2 class=\"title\">\K${DOMAIN_REGEX}" \
        > "$source_results"
}

source_scamadviser() {
    # Last checked: 06/03/25
    source_url='https://www.scamadviser.com/articles'

    curl -sSLZ --retry 2 --retry-all-errors "${source_url}?p=[1-15]" \
        | grep -Po "[A-Z0-9][-.]?${DOMAIN_REGEX}(?= ([A-Z]|a ))" \
        > "$source_results"
}

source_scamdirectory() {
    # Last checked: 17/02/25
    source_url='https://scam.directory/category'

    # head -n causes grep broken pipe error
    curl -sSL --retry 2 --retry-all-errors "$source_url" \
        | grep -Po "<span>\K${DOMAIN_REGEX}(?=<br>)" > "$source_results"
}

source_scamminder() {
    # Last checked: 10/03/25
    source_url='https://scamminder.com/websites'

    # There are about 150 new pages daily
    curl -sSLZ --retry 2 --retry-all-errors "${source_url}/page/[1-200]" \
        | mawk '/Trust Score :  strongly low/ { getline; print }' \
        | grep -Po "class=\"h5\">\K${DOMAIN_REGEX}" > "$source_results"
}

source_scamscavenger() {
    # Last checked: 10/03/25
    source_url='https://raw.githubusercontent.com/jarelllama/Blocklist-Sources/refs/heads/main/scamscavenger.txt'

    curl -sSL --retry 2 --retry-all-errors "$source_url" -o "$source_results"
}

source_scamtracker() {
    # Last checked: 22/02/25
    source_url='https://scam-tracker.net/category/crypto-scams'
    local -a review_urls

    # Add URLs of reviews into an array
    mapfile -t review_urls \
        < <(curl -sSLZ --retry 2 --retry-all-errors "${source_url}/page/[1-100]" \
        | grep -Po '"headline"><a href="\Khttps://scam-tracker.net/crypto-scams/.*(?=/" rel="bookmark">)')

    curl -sSLZ --retry 2 --retry-all-errors "${review_urls[@]}" \
        | grep -Po "<div class=\"review-value\">\K${DOMAIN_REGEX}(?=</div>)" \
        > "$source_results"
}

source_unit42() {
    # Last checked: 10/03/25
    source_url='https://github.com/PaloAltoNetworks/Unit42-timely-threat-intel/archive/refs/heads/main.zip'

    curl -sSL --retry 2 --retry-all-errors "$source_url" -o unit42.zip
    unzip -q unit42.zip -d unit42

    grep -hPo "hxxps?\[:\]//\K${DOMAIN_SQUARE_REGEX}|^- \K${DOMAIN_SQUARE_REGEX}" \
        unit42/*/"$(date +%Y)"* > "$source_results"

    rm -r unit42*
}

source_viriback_tracker() {
    # Last checked: 10/03/25
    source_url='https://tracker.viriback.com/last30.php'

    curl -sSL --retry 2 --retry-all-errors "$source_url" \
        | grep -Po ",https?://\K${DOMAIN_REGEX}" > "$source_results"
}

source_vzhh() {
    # Last checked: 17/02/25
    source_url='https://www.vzhh.de/themen/einkauf-reise-freizeit/einkauf-online-shopping/fake-shop-liste-wenn-guenstig-richtig-teuer-wird'

    curl -sSL --retry 2 --retry-all-errors "$source_url" \
        | grep -Po "field--item\">\K${DOMAIN_REGEX}(?=</div>)" \
        > "$source_results"
}

source_wipersoft() {
    # Last checked: 10/03/25
    source_url='https://www.wipersoft.com/blog'

    curl -sSLZ --retry 2 --retry-all-errors "${source_url}/page/[1-15]" \
        | mawk '/<div class="post-content">/ { getline; print }' \
        | grep -Po "${DOMAIN_REGEX}" > "$source_results"
}

# Entry point

set -e

trap cleanup EXIT

$FUNCTION --format-files

main

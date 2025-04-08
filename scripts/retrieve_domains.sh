#!/bin/bash

# Retrieve domains from the sources, process them, and output a raw file
# that contains the cumulative domains from all sources over time.

readonly FUNCTION='bash scripts/tools.sh'
readonly RUN_SOURCE='bash scripts/sources.sh'
readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly PENDING='data/pending'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly REVIEW_CONFIG='config/review_config.csv'
readonly SOURCES_CONFIG='config/sources.csv'
readonly SOURCE_LOG='config/source_log.csv'
# '[\p{L}\p{N}][\p{L}\p{N}-]*[\p{L}\p{N}]' matches the root domain and subdomains
# '[\p{L}\p{N}]' matches single character subdomains
# '[\p{L}}][\p{L}\p{N}-]*[\p{L}\p{N}]' matches the TLD (TLDs can not start with a number)
# Does NOT match periods enclosed by square brackets
readonly DOMAIN_REGEX='(?:([\p{L}\p{N}][\p{L}\p{N}-]*[\p{L}\p{N}]|[\p{L}\p{N}])\.)+[\p{L}}][\p{L}\p{N}-]*[\p{L}\p{N}]'

main() {
    $FUNCTION --download-toplist

    $FUNCTION --update-review-config

    # Store the whitelist and blacklist as regex expressions
    whitelist="$($FUNCTION --get-whitelist)"
    blacklist="$($FUNCTION --get-blacklist)"
    readonly whitelist blacklist

    # Install idn2 here instead of in $FUNCTION to not bias the source
    # processing time
    command -v idn2 > /dev/null || sudo apt-get install idn2 > /dev/null

    # Check whether to use existing results in the pending directory or
    # or retrieve new results
    if [[ -d "$PENDING" ]]; then
        printf "\nUsing existing retrieved results.\n"

        process_existing_results
    else
        mkdir -p "$PENDING"

        $FUNCTION --download-nrd-feed

        # Install jq
        command -v jq > /dev/null || sudo apt-get install jq > /dev/null

        retrieve_new_results
    fi

    # Remove duplicates from the review config file
    # This is done here once instead of multiple times in filter()
    mawk '!seen[$0]++' "$REVIEW_CONFIG" > temp
    mv temp "$REVIEW_CONFIG"

    save_domains
}

# Process sources and results from the pending directory.
process_existing_results() {
    local source_results source_name execution_time

    # Loop through the existing results
    for source_results in "$PENDING"/*.tmp; do
        [[ ! -f "$source_results" ]] && return

        # Get the source name
        # Remove file path
        source_name="${source_results##*/}"
        # Remove file extension
        source_name="${source_name%.tmp}"
        # Replace underscores with spaces
        source_name="${source_name//_/ }"

        printf "\n\e[1mSource: %s\e[0m\n" "$source_name"

        # Check if the source is in the sources config file, excluding manual
        # additions
        if ! grep -q "^${source_name}," "$SOURCES_CONFIG" &&
            [[ "$source_name" != 'Manual' ]]; then
            printf "Note: source not found in sources config file.\n"
        fi

        execution_time="$(date +%s)"

        process_source
    done
}

# Process and retrieve source results from enabled sources in the sources
# config file.
retrieve_new_results() {
    local source_results execution_time

    # Loop through the enabled sources
    while IFS=',' read -r source_name source_function; do
        source_results="${PENDING}/${source_name// /_}.tmp"

        printf "\n\e[1mSource: %s\e[0m\n" "$source_name"

        execution_time="$(date +%s)"

        # Run the source function to retrieve results
        $RUN_SOURCE "$source_function"

        # Ensure the source results file is present
        touch results.tmp
        mv results.tmp "$source_results"

        process_source
    done <<< "$(mawk -F ',' '$4 == "y" { print $1 "," $2 }' "$SOURCES_CONFIG")"
}

# Used by process_source() to remove entries from the source results
# file and to log them into the domain log.
# Input:
#   $1: entries to process in a variable
#   $2: tag to be shown in the domain log
#   --no-log:   do not log entries into the domain log
#   --preserve: save entries for manual review and for rerun
# Output:
#   Number of entries that were passed
filter() {
    local entries="$1"
    local tag="$2"

    # Return with 0 entries if no entries were found
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

        # Save entries to use in rerun
        printf "%s\n" "$entries" >> "${source_results}.tmp"
    fi

    # Return the number of entries
    wc -l <<< "$entries"
}

# Process and filter the results from the source, append the resulting domains
# to all_filtered_domains.tmp/all_filtered_light_domains.tmp, and save
# entries requiring manual review.
process_source() {
    local raw_count dead_count parked_count whitelisted_count
    local whitelisted_tld_count in_toplist_count filtered_count
    local too_large=false

    sort -u "$source_results" -o "$source_results"

    # Count the number of unfiltered results
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
    # Redirect output to /dev/null as the invalid entries count is not used
    filter "$(grep -vP "^${DOMAIN_REGEX}$" "$source_results")" \
        invalid --preserve > /dev/null

    # Convert Unicode to Punycode
    $FUNCTION --convert-unicode "$source_results"

    # Remove known dead domains
    dead_count="$(filter \
        "$(comm -12 <(sort "$DEAD_DOMAINS") "$source_results")" \
        dead --no-log)"

    # Remove known parked domains
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
        # Empty source results to ensure the results are not saved
        : > "$source_results"
    fi

    # Get blacklisted domains
    # This is done here once instead of multiple regex matches below
    mawk -v blacklist="$blacklist" '$0 ~ blacklist' "$source_results" \
        > blacklisted.tmp

    # Temporarily remove blacklisted domains from the source results
    comm -23 "$source_results" blacklisted.tmp > temp
    mv temp "$source_results"

    # Log blacklisted domains
    $FUNCTION --log-domains blacklisted.tmp blacklist "$source_name"

    # Remove whitelisted domains
    # awk is used here instead of mawk for compatibility with the regex
    # expression
    whitelisted_count="$(filter \
        "$(awk -v whitelist="$whitelist" '$0 ~ whitelist' "$source_results"
    )" whitelist)"

    # Remove domains with whitelisted TLDs
    # awk is used here instead of mawk for compatibility with the regex
    # expression
    whitelisted_tld_count="$(filter \
        "$(awk '/\.(gov|edu|mil)(\.[a-z]{2})?$/' "$source_results"
    )" whitelisted_tld --preserve)"

    # Remove domains found in the toplist
    in_toplist_count="$(filter \
        "$(comm -12 "$source_results" toplist.tmp)" toplist --preserve)"

    # Add back blacklisted domains
    sort -u blacklisted.tmp "$source_results" -o "$source_results"
    rm blacklisted.tmp

    # Count the number of filtered domains
    filtered_count="$(wc -l < "$source_results")"

    # Collate filtered domains
    cat "$source_results" >> all_filtered_domains.tmp

    # Check if the source is excluded from the light version
    if [[ -z "$(mawk -v source="$source_name" -F ',' '
        $1 == source { print $3 }' "$SOURCES_CONFIG")" ]]; then
        cat "$source_results" >> all_filtered_light_domains.tmp
    fi

    log_source

    rm "$source_results"

    if [[ -f "${source_results}.tmp" ]]; then
        # Save entries that are pending manual review for rerun
        mv "${source_results}.tmp" "$source_results"
    fi
}

# Print and log statistics for each source.
log_source() {
    local total_whitelisted_count status

    total_whitelisted_count="$(( whitelisted_count + whitelisted_tld_count ))"

    if (( raw_count == 0 )); then
        status='ERROR: empty'

        printf "\e[1;31mNo results retrieved. Potential error occurred.\e[0m\n"

        $FUNCTION --send-telegram \
            "Warning: '$source_name' retrieved no results. Potential error occurred."

    elif [[ "$too_large" == true ]]; then
        status='ERROR: too_large'

        printf "\e[1;31mSource is unusually large (%s entries). Not saving.\e[0m\n" \
            "$(wc -l < "${source_results}.tmp")"

        $FUNCTION --send-telegram \
            "Warning: '$source_name' is unusually large ($(wc -l < "${source_results}.tmp") entries). Potential error occurred."

    else
        status='saved'

        printf "Raw:%4s  Final:%4s  Whitelisted:%4s  Excluded:%4s  Toplist:%4s\n" \
            "$raw_count" "$filtered_count" "$total_whitelisted_count" \
            "$(( dead_count + parked_count ))" "$in_toplist_count"
    fi

    printf "Processing time: %s seconds\n" "$(( $(date +%s) - execution_time ))"
    printf -- "----------------------------------------------------------------------\n"

    # Log source into the source log
    printf "%s,%s,%s,%s,%s,%s,%s,%s,%s\n" >> "$SOURCE_LOG" \
        "$(TZ=Asia/Singapore date +"%H:%M:%S %d-%m-%y")" "$source_name" \
        "$raw_count" "$filtered_count" "$total_whitelisted_count" \
        "$dead_count" "$parked_count" "$in_toplist_count" "$status"

    # Log source into the domain log
    $FUNCTION --log-domains "$source_results" saved "$source_name"
}

# Save filtered domains into the raw file.
save_domains() {
    local count_before count_after

    # Print domains requiring manual review to console
    if [[ -f entries_for_review.tmp ]]; then
        printf "\n\e[1mEntries requiring manual review:\e[0m\n"
        sed 's/(/(\o033[31m/; s/)/\o033[0m)/' entries_for_review.tmp

        $FUNCTION --send-telegram \
            "Retrieval: entries requiring manual review\n\n$(<entries_for_review.tmp)"

        printf "\nTelegram notification sent.\n"
    fi

    if [[ ! -s all_filtered_domains.tmp ]]; then
        printf "\n\e[1mNo new domains to add.\e[0m\n"
        return
    fi

    count_before="$(wc -l < "$RAW")"

    # Save domains to the raw file
    sort -u all_filtered_domains.tmp "$RAW" -o "$RAW"

    # Save domains to the raw light file
    if [[ -s all_filtered_light_domains.tmp ]]; then
        sort -u all_filtered_light_domains.tmp "$RAW_LIGHT" -o "$RAW_LIGHT"
    fi

    count_after="$(wc -l < "$RAW")"

    printf "\nAdded new domains to raw file.\nBefore: %s  Added: %s  After: %s\n" \
        "$count_before" "$(( count_after - count_before ))" "$count_after"

    # Delete the pending directory if empty (no domains saved for rerun)
    find "$PENDING" -type d -empty -delete
}

# Entry point

set -e

trap 'rm ./*.tmp 2> /dev/null || true' EXIT

$FUNCTION --format-files

main

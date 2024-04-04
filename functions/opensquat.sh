#!/bin/bash

# Uses openSquat to find phishing domains from a list of newly
# registered domains.

readonly RAW='data/raw.txt'
readonly KEYWORDS='config/opensquat_keywords.txt'
readonly NRD='lists/wildcard_domains/nrd.txt'
readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'

opensquat() {
    results_file='data/pending/domains_opensquat.tmp'

    # Create results file for proper logging
    mkdir -p data/pending
    touch "$results_file"

    # Install openSquat
    git clone -q https://github.com/atenreiro/opensquat
    pip install -qr opensquat/requirements.txt

    # Collate fresh NRD list and exit if any link is broken
    {
        wget -qO - 'https://raw.githubusercontent.com/shreshta-labs/newly-registered-domains/main/nrd-1w.csv' \
            || exit 1
        wget -qO - 'https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/nrds.10-onlydomains.txt' \
            | grep -vF '#' || exit 1
        curl -sH 'User-Agent: openSquat-2.1.0' 'https://feeds.opensquat.com/domain-names.txt' \
            || exit 1
    } >> "$NRD"

    bash functions/tools.sh format "$NRD"

    # Filter out previously processed domains and known dead/parked domains
    comm -23 "$NRD" <(sort "$RAW" "$DEAD_DOMAINS" "$PARKED_DOMAINS") \
        > nrd.tmp

    # Exit if no domains to process
    if [[ ! -s nrd.tmp ]]; then
        printf "No new domains to process.\n"
        exit
    fi

    print_splashcreen

    # Split file into 12 equal files
    split -d -l $(( $(wc -l < nrd.tmp) / 12 )) nrd.tmp

    # Run retrieval in parallel
    run_opensquat x00 & run_opensquat x01 & run_opensquat x02 &
    run_opensquat x03 & run_opensquat x04 & run_opensquat x05 &
    run_opensquat x06 & run_opensquat x07 & run_opensquat x08 &
    run_opensquat x09 & run_opensquat x10 & run_opensquat x11 &
    run_opensquat x12 & run_opensquat x13
    wait
    rm x??

    # Collate results (ignore not found errors)
    cat results_x??.tmp > "$results_file" 2> /dev/null
    rm results_x??.tmp 2> /dev/null

    format_file "$results_file"

    # Print results
    while read -r keyword; do
        printf "\n[*] Verifying keyword: %s [ %s / %s ]\n" \
            "$keyword" "$((++i))" "$(wc -l < "$KEYWORDS")"
        results="$(grep -F -- "$keyword" "$results_file")" \
            && awk '{print "[+] Found " $0}' <<< "$results"
        printf "\n"
    done < "$KEYWORDS"

    print_summary
}

# Function 'run_opensquat' runs openSquat for the given file.
# Input:
#   $1: file to process
# Output:
#   results_x??.tmp
run_opensquat() {
    [[ ! -f "$1" ]] && return
    python3 opensquat/opensquat.py -k "$KEYWORDS" -c 0 -d "$1" \
        -o "results_${1}.tmp" &> /dev/null
}

# Function 'print_splashscreen' prints the modified openSquat splashscreen.
print_splashcreen() {
    printf "\n\e[1mopenSquat\e[0m
https://github.com/atenreiro/opensquat
(c) Andre Tenreiro under the GNU GPLv3 license\n
+---------- Checking Domain Squatting ----------+
[*] keywords: %s
[*] keywords total: %s
[*] Total domains: %s
[*] Threshold: very high confidence\n\n" \
    "$KEYWORDS" "$(wc -l < "$KEYWORDS")" \
    "$(wc -l < nrd.tmp | rev | sed 's/\(...\)/\1,/g' | sed 's/,$//' | rev)"

    # Record start time
    execution_time="$(date +%s)"
}

# Function 'print_summary' prints the modified openSquat summary.
print_summary() {
    # Record end time
    end_time="$(date +%s)"

    printf "\n+---------- Summary Squatting ----------+
[*] Domains flagged: %s
[*] Domains result: %s
[*] Running time: %s seconds\n\n" \
    "$(wc -l < "$results_file")" "$results_file" "$(( end_time - execution_time ))"
}

# Function 'format_file' calls a shell wrapper to standardize the format
# of a file.
#   $1: file to format
format_file() {
    bash functions/tools.sh format "$1"
}

cleanup() {
    # Delete openSquat
    rm -rf opensquat

    find . -maxdepth 1 -type f -name "*.tmp" -delete
}

# Entry point

trap cleanup EXIT

for file in config/* data/*; do
    format_file "$file"
done

opensquat
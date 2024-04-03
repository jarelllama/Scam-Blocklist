#!/bin/bash

# Uses openSquat to find phishing domains from a list of newly
# registered domains.

readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly KEYWORDS='config/opensquat_keywords.txt'
readonly NRD='lists/wildcard_domains/nrd.txt'

opensquat() {
    mkdir -p data/pending
    # Create results file for proper logging
    touch data/pending/domains_opensquat.txt

    # Install openSquat
    git clone -q https://github.com/atenreiro/opensquat
    pip install -qr opensquat/requirements.txt

    # Save previous NRD list for comparison
    touch "$NRD" && mv "$NRD" old_nrd.tmp

    # Collate fresh NRD list and exit with status 1 if any link is broken
    {
        wget -qO - 'https://raw.githubusercontent.com/shreshta-labs/newly-registered-domains/main/nrd-1w.csv' \
            || exit 1
        wget -qO - 'https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/nrds.10-onlydomains.txt' \
            | grep -vF '#' || exit 1
        curl -sH 'User-Agent: openSquat-2.1.0' 'https://feeds.opensquat.com/domain-names.txt' \
            || exit 1
    } >> "$NRD"

    bash functions/tools.sh format "$NRD"

    # Filter out previously processed domains and known dead or parked domains
    #comm -23 "$NRD" <(sort old_nrd.tmp "$DEAD_DOMAINS" "$PARKED_DOMAINS") > new_nrd.tmp
    mv "$NRD" new_nrd.tmp  # FOR DEBUGGING

    # Exit if no domains to process
    [[ ! -s new_nrd.tmp ]] && exit

    # Split file into 12 equal files
    split -d -l $(( $(wc -l < new_nrd.tmp) / 12 )) new_nrd.tmp

    # Run retrieval in parallel
    run_opensquat x00 & run_opensquat x01 & run_opensquat x02 &
    run_opensquat x03 & run_opensquat x04 & run_opensquat x05 &
    run_opensquat x06 & run_opensquat x07 & run_opensquat x08 &
    run_opensquat x09 & run_opensquat x10 & run_opensquat x11 &
    run_opensquat x12 & run_opensquat x13
    wait
    rm x??

    # Collate domains
    cat results_x??.tmp > data/pending/domains_opensquat.tmp 2> /dev/null
    rm results_x??.tmp 2> /dev/null

    format_file data/pending/domains_opensquat.tmp
}

run_opensquat() {
    [[ ! -f "$1" ]] && return
    python3 opensquat/opensquat.py -k "$KEYWORDS" -c 0 -d "$1" -o "results_${1}.tmp"
}

# Function 'format_file' calls a shell wrapper to standardize the format
# of a file.
#   $1: file to format
format_file() {
    bash functions/tools.sh format "$1"
}

cleanup() {
    # Delete openSquat
    rm -r opensquat

    find . -maxdepth 1 -type f -name "*.tmp" -delete
}

# Entry point

trap cleanup EXIT

for file in config/* data/*; do
    format_file "$file"
done

opensquat
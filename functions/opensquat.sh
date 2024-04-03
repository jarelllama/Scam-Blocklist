#!/bin/bash

# Uses openSquat to find phishing domains from a list of newly
# registered domains.

readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly KEYWORDS='config/opensquat_keywords.txt'
readonly NRD='lists/wildcard_domains/nrd.txt'

opensquat() {
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
    comm -23 "$NRD" <(sort old_nrd.tmp "$DEAD_DOMAINS" "$PARKED_DOMAINS") > new_nrd.tmp

     # Split file into 12 equal files
    split -d -l $(( $(wc -l < new_nrd.txt) / 12 )) new_nrd.txt

    # Run checks in parallel
    python3 opensquat.py -k "$KEYWORDS" -c 0 -d x00 -o results_x00.txt &
    python3 opensquat.py -k "$KEYWORDS" -c 0 -d x01 -o results_x01.txt &
    python3 opensquat.py -k "$KEYWORDS" -c 0 -d x02 -o results_x02.txt &
    python3 opensquat.py -k "$KEYWORDS" -c 0 -d x03 -o results_x03.txt &
    python3 opensquat.py -k "$KEYWORDS" -c 0 -d x04 -o results_x04.txt &
    python3 opensquat.py -k "$KEYWORDS" -c 0 -d x05 -o results_x05.txt &
    python3 opensquat.py -k "$KEYWORDS" -c 0 -d x06 -o results_x06.txt &
    python3 opensquat.py -k "$KEYWORDS" -c 0 -d x07 -o results_x07.txt &
    python3 opensquat.py -k "$KEYWORDS" -c 0 -d x08 -o results_x08.txt &
    python3 opensquat.py -k "$KEYWORDS" -c 0 -d x09 -o results_x09.txt &
    python3 opensquat.py -k "$KEYWORDS" -c 0 -d x10 -o results_x10.txt &
    python3 opensquat.py -k "$KEYWORDS" -c 0 -d x11 -o results_x11.txt &
    python3 opensquat.py -k "$KEYWORDS" -c 0 -d x12 -o results_x12.txt &
    python3 opensquat.py -k "$KEYWORDS" -c 0 -d x13 -o results_x13.txt
    wait
    rm x??

    mkdir -p data/pending

    cat results_x??.txt > data/pending/domains_opensquat.tmp 2> /dev/null
    rm results_x??.txt 2> /dev/null

    format_file data/pending/domains_opensquat.tmp
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
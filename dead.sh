#!/bin/bash
raw_file='data/raw.txt'
adblock_file='lists/adblock/scams.txt'
wildcards_file='data/wildcards.txt'
dead_domains_file='data/dead_domains.txt'
domain_log='data/domain_log.csv'
time_format="$(TZ=Asia/Singapore date +"%H:%M:%S %d-%m-%y")"

function main {
    format_list "$raw_file"
    format_list "$wildcards_file"
    format_list "$domain_log"

    npm i -g @adguard/dead-domains-linter  # Install AdGuard Dead Domains Linter
    dead-domains-linter --import "$adblock_file" --export dead.tmp  # Run Linter and export dead domains
    comm -23 dead.tmp "$wildcards_file"  # Exclude wildcard domains
    # Exit early if no dead domains found
    if [[ ! -s dead.tmp ]]; then
        rm dead.tmp
        exit
    fi
    comm -23 "$raw_file" dead.tmp > raw.tmp && mv raw.tmp "$raw_file"  # Remove dead domains from raw file
    cat dead.tmp >> "$dead_domains_file"  # Collate dead domains
    format_list "$dead_domains_file"
    log_event "$<(dead.tmp)" "dead"
    rm dead.tmp
}

function log_event {
    # Log domain processing events
    printf "%s" "$1" | awk -v event="$2" -v time="$time_format" '{print time "," event "," $0 ",raw"}' >> "$domain_log"
}

function format_list {
    [[ -f "$1" ]] || return  # Return if file does not exist
    # If file is a CSV file, do not sort
    if [[ "$1" == *.csv ]]; then
        sed -i 's/\r$//' "$1"  
        return
    fi
    # Format carriage return characters, remove empty lines, sort and remove duplicates
    tr -d '\r' < "$1" | sed '/^$/d' | sort -u > "${1}.tmp" && mv "${1}.tmp" "$1"
}

main


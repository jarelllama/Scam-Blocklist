#!/bin/bash
raw_file='data/raw.txt'
adblock_file='lists/adblock/scams.txt'
wildcards_file='data/wildcards.txt'
dead_domains_file='data/dead_domains.txt'
domain_log='data/domain_log.csv'
time_format="$(TZ=Asia/Singapore date +"%H:%M:%S %d-%m-%y")"

function main {
    npm i -g @adguard/dead-domains-linter  # Install AdGuard Dead Domains Linter
    format_list "$raw_file"
    format_list "$wildcards_file"
    format_list "$domain_log"

    touch dead.tmp  # Intitialize temp file for dead domains
    dead-domains-linter --i "$dead_domains_file" --export dead.tmp  # Find dead domains in the dead domains file
    mv dead.tmp "$dead_domains_file"  # Update dead domains file to include only dead domains
    format_list "$dead_domains_file"
    comm -23 "$dead_domains_file" dead.tmp > alive.tmp  # Find resurrected domains in the dead domains file
    if [[ -s alive.tmp ]]; then
        cat alive.tmp > "$raw_file"  # Add resurrected domains to the raw file
        format_list "$raw_file"
        log_event "$(<alive.tmp)" "resurrected"
    fi
    rm dead.tmp
    rm alive.tmp

    dead-domains-linter --i "$adblock_file" --export dead.tmp  # Find and export dead domains
    temp_dead=$(comm -23 dead.tmp "$wildcards_file") && printf "%s" "$temp_dead" > dead.tmp  # Exclude wildcard domains
    # Exit early if no dead domains found
    if [[ ! -s dead.tmp ]]; then
        rm dead.tmp
        exit
    fi
    comm -23 "$raw_file" dead.tmp > raw.tmp && mv raw.tmp "$raw_file"  # Remove dead domains from raw file
    cat dead.tmp >> "$dead_domains_file"  # Collate dead domains
    format_list "$dead_domains_file"
    log_event "$(<dead.tmp)" "dead"
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


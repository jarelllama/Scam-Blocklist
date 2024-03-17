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
    format_list "$dead_domains_file"
    check_alive
    check_dead
}   

function check_alive {
    dead-domains-linter -i "$dead_domains_file" --export dead.tmp  # Find dead domains in the dead domains file
    alive_domains=$(comm -23 "$dead_domains_file" dead.tmp) # Find resurrected domains in the dead domains file
    # Return early if no alive domains found
    if [[ -z "$alive_domains" ]]; then
        rm dead.tmp
        return
    fi
    cp dead.tmp "$dead_domains_file"  # Update dead domains file to include only dead domains
    printf "%s\n" "$alive_domains" >> "$raw_file"  # Add resurrected domains to the raw file
    format_list "$raw_file"
    log_event "$alive_domains" "resurrected"
    rm dead.tmp
}

function check_dead {
    dead-domains-linter -i "$adblock_file" --export dead.tmp  # Find and export dead domains
    # Exclude wildcard domains
    dead_domains=$(comm -23 dead.tmp "$wildcards_file")
    rm dead.tmp
    [[ -z "$dead_domains" ]] && return  # Return early if no dead domains found
    # Remove dead domains from raw file
    comm -23 "$raw_file" <(printf "%s" "$dead_domains") > raw.tmp && mv raw.tmp "$raw_file"
    printf "%s\n" "$dead_domains" >> "$dead_domains_file"  # Collate dead domains
    format_list "$dead_domains_file"
    log_event "$dead_domains" "dead"
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


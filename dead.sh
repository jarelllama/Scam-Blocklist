#!/bin/bash
raw_file='data/raw.txt'
wildcards_file='data/wildcards.txt'
dead_domains_file='data/dead_domains.txt'
domain_log='data/domain_log.csv'
time_format="$(TZ=Asia/Singapore date +"%H:%M:%S %d-%m-%y")"

function main {
    format_list "$raw_file"
    format_list "$wildcards_file"
    format_list "$domain_log"
    check_dead
}

function check_dead {
    touch dead.tmp  # Initialize temp file for dead domains
    while read -r domain; do  # Loop through domains in the blocklist
        if host -t a "$domain" | grep -q 'has no A record'; then  # Check if the domain has an A record
            printf "%s\n" "$domain" >> dead.tmp
        fi
    done <<< "$(comm -23 "$raw_file" "$wildcards_file")"  # Exclude wildcards as they might not have A records but block subdomains that do
    format_list dead.tmp
    comm -23 "$raw_file" dead.tmp > "${raw_file}.tmp" && mv "${raw_file}.tmp" "$raw_file"  # Remove dead domains
    log_event "$(<dead.tmp)" "dead"
    cat dead.tmp >> "$dead_domains_file"
    format_list "$dead_domains_file"
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


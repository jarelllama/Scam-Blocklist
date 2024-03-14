#!/bin/bash
raw_file='data/raw.txt'
dead_domains_file='data/dead_domains.txt'
domain_log='data/domain_log.csv'
time_format="$(TZ=Asia/Singapore date +"%H:%M:%S %d-%m-%y")"

function main {
    format_list "$raw_file"
    check_dead
    save_and_exit 0
}

function check_dead {
    while read -r domain; do  # Loop through domains in the blocklist
        if host -t a "$domain" | grep -q 'has no A record'; then  # Check if the domain has an A record
            echo -n "$domain" >> dead.tmp
            echo -n "$domain" >> "$dead_domains_file"
        fi
    done < "$raw_file"
    format_list dead.tmp
    format_list "$dead_domains_file"
    log_event dead.tmp "dead"
    cp "$raw_file" "${raw_file}.bak"  # Backup raw file
    comm -23 "$raw_file" dead.tmp > "${raw_file}.tmp" && mv "${raw_file}.tmp" "$raw_file"  # Remove dead domains
    [[ -f dead.tmp ]] && rm dead.tmp
}

function log_event {
    # Log domain processing events
    echo -n "$1" | awk -v event="$2" -v time="$time_format" '{print time "," event "," $0 ",raw"}' >> "$domain_log"
}

function format_list {
    # Format carriage return characters, remove empty lines, sort and remove duplicates
    tr -d '\r' < "$1" | sed '/^$/d' | sort -u > "${1}.tmp" && mv "${1}.tmp" "$1"
}

function save_and_exit {
    exit_code="$1"
    # If running locally, exit without pushing changes to repository
    if [[ "$CI" != true ]]; then
        sleep 0.5
        echo -e "\nScript is running locally. No changes were pushed."
        exit "$exit_code"
    fi
    git add .
    git commit -m "List maintenance"
    git push -q
    exit "$exit_code"
}

main


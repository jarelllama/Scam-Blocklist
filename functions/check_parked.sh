#!/bin/bash
raw_file='data/raw.txt'
raw_light_file='data/raw_light.txt'
parked_terms_file='config/parked_terms.txt'
parked_domains_file='data/parked_domains.txt'
domain_log='config/domain_log.csv'
time_format=$(date -u +"%H:%M:%S %d-%m-%y")

function main {
    for file in config/* data/*; do  # Format files in the config and data directory
        format_list "$file"
    done
    remove_parked_domains
    add_unparked_domains
    cat parked_domains.tmp >> "$parked_domains_file"  # Collate parked domains (skip unparked check)
    format_list "$parked_domains_file"
    update_light_file
}

function remove_parked_domains {
    touch parked_domains.tmp
    printf "\n[start] Analyzing %s entries for parked domains\n" "$(wc -l < "$raw_file")"

    # Split into 12 equal files
    split -d -l $(($(wc -l < "$raw_file")/12)) "$raw_file"
    check_parked "x00" & check_parked "x01" &
    check_parked "x02" & check_parked "x03" &
    check_parked "x04" & check_parked "x05" &
    check_parked "x06" & check_parked "x07" &
    check_parked "x08" & check_parked "x09" &
    check_parked "x10" & check_parked "x11" &
    check_parked "x12" & check_parked "x13"
    wait

    [[ ! -s parked_domains.tmp ]] && return
    format_list parked_domains.tmp

    # Remove parked domains from raw file
    comm -23 "$raw_file" parked_domains.tmp > raw.tmp && mv raw.tmp "$raw_file"
    log_event "$(<parked_domains.tmp)" "parked" "raw"
    find . -maxdepth 1 -type f -name "x??" -delete  # Reset split files
}

function add_unparked_domains {
    touch unparked_domains.tmp
    printf "\n[start] Analyzing %s entries for unparked domains\n" "$(wc -l < "$raw_file")"

    # Split into 12 equal files
    split -d -l $(($(wc -l < "$parked_domains_file")/12)) "$parked_domains_file"
    check_unparked "x00" & check_unparked "x01" &
    check_unparked "x02" & check_unparked "x03" &
    check_unparked "x04" & check_unparked "x05" &
    check_unparked "x06" & check_unparked "x07" &
    check_unparked "x08" & check_unparked "x09" &
    check_unparked "x10" & check_unparked "x11" &
    check_unparked "x12" & check_unparked "x13"
    wait

    [[ ! -s unparked_domains.tmp ]] && return
    format_list unparked_domains.tmp

    # Remove unparked domains from parked domains file (parked domains file is unsorted)
    grep -vxFf unparked_domains.tmp "$parked_domains_file" > parked.tmp && mv parked.tmp "$parked_domains_file"
    cat unparked_domains.tmp >> "$raw_file"  # Add unparked domains to raw file
    format_list "$raw_file"
    log_event "$(<unparked_domains.tmp)" "unparked" "parked_domains_file"
    find . -maxdepth 1 -type f -name "x??" -delete  # Reset split files before next run
}

function check_parked {
    [[ ! -f "$1" ]] && return  # Return if split file not found
    [[ "$1" == 'x00' ]] && { track=true; count=0; } || track=false  # Track progress for first split file
    while read -r domain; do
        ((count++))
        # Check for parked message in site's HTML
        if grep -qiFf "$parked_terms_file" <<< "$(curl -sL --max-time 2 "http://${domain}/" | tr -d '\0')"; then
            printf "[info] Found parked domain: %s\n" "$domain"
            printf "%s\n" "$domain" >> "parked_domains_${1}.tmp"
        fi
        [[ "$track" == false ]] && continue  # Skip progress tracking if not first split file
        ((count % 100 == 0)) && printf "[info] Analyzed %s%% of domains\n" "$((count * 100 / $(wc -l < "$1")))"
    done < "$1"
    # Collate parked domains
    [[ -f "parked_domains_${1}.tmp" ]] && cat "parked_domains_${1}.tmp" >> parked_domains.tmp
}

function check_unparked {
    [[ ! -f "$1" ]] && return  # Return if split file not found
    [[ "$1" == 'x00' ]] && { track=true; count=0; } || track=false  # Track progress for first split file
    while read -r domain; do
        ((count++))
        # Check for parked message in site's HTML
        if ! grep -qiFf "$parked_terms_file" <<< "$(curl -sL --max-time 5 "http://${domain}/" | tr -d '\0')"; then
            printf "[info] Found unparked domain: %s\n" "$domain"
            printf "%s\n" "$domain" >> "unparked_domains_${1}.tmp"
        fi
        [[ "$track" == false ]] && continue  # Skip progress tracking if not first split file
        ((count % 100 == 0)) && printf "[info] Analyzed %s%% of domains\n" "$((count * 100 / $(wc -l < "$1")))"
    done < "$1"
    # Collate unparked domains
    [[ -f "unparked_domains_${1}.tmp" ]] && cat "unparked_domains_${1}.tmp" >> unparked_domains.tmp
}

function update_light_file {
    comm -12 "$raw_file" "$raw_light_file" > light.tmp && mv light.tmp "$raw_light_file"  # Keep only domains found in full raw file
}

function prune_parked_domains_file {
    [[ $(wc -l < "$parked_domains_file") -gt 4000 ]] && sed -i '1,100d' "$parked_domains_file" || printf ""  # printf to negate exit status 1
}

function log_event {
    # Log domain events
    printf "%s\n" "$1" | awk -v type="$2" -v source="$3" -v time="$time_format" '{print time "," type "," $0 "," source}' >> "$domain_log"
}

function format_list {
    bash functions/tools.sh "format" "$1"
}

function cleanup {
    find . -maxdepth 1 -type f -name "*.tmp" -delete
    find . -maxdepth 1 -type f -name "x??" -delete
    prune_parked_domains_file
}

trap cleanup EXIT
main

#!/bin/bash
raw_file='data/raw.txt'
raw_light_file='data/raw_light.txt'
domain_log='config/domain_log.csv'
root_domains_file='data/root_domains.txt'
subdomains_file='data/subdomains.txt'
subdomains_to_remove_file='config/subdomains.txt'
wildcards_file='data/wildcards.txt'
redundant_domains_file='data/redundant_domains.txt'
dead_domains_file='data/dead_domains.txt'
time_format=$(date -u +"%H:%M:%S %d-%m-%y")

function main {
    npm i -g @adguard/dead-domains-linter  # Install AdGuard Dead Domains Linter
    for file in config/* data/*; do  # Format files in the config and data directory
        format_list "$file"
    done
    check_for_alive
    check_subdomains
    check_redundant
    check_for_dead
    update_light_file
}

function check_for_alive {
    sed 's/^/||/; s/$/^/' "$dead_domains_file" > formatted_dead_domains_file.tmp  # Format dead domains file

    # Process in 6 parallel runs
    split -n 6 -d formatted_dead_domains_file.tmp
    dead-domains-linter -i x00 --export x00.tmp & dead-domains-linter -i x01 --export x01.tmp &
    dead-domains-linter -i x02 --export x02.tmp & dead-domains-linter -i x03 --export x03.tmp &
    dead-domains-linter -i x04 --export x04.tmp & dead-domains-linter -i x05 --export x05.tmp
    cat x*.tmp >> dead.tmp  # note dead domains file is unsorted

    alive_domains=$(comm -23 <(sort "$dead_domains_file") <(sort dead.tmp))  # Find resurrected domains in the dead domains file
    [[ -z "$alive_domains" ]] && return  # Return if no resurrected domains found
    cp dead.tmp "$dead_domains_file"  # Update dead domains file to exclude resurrected domains
    printf "%s\n" "$alive_domains" >> "$raw_file"  # Add resurrected domains to raw file
    format_list "$dead_domains_file" && format_list "$raw_file"
    log_event "$alive_domains" "resurrected" "dead_domains_file"
}

function check_subdomains {
    sed 's/^/||/; s/$/^/' "$subdomains_file" > formatted_subdomains_file.tmp  # Format subdomains file
    dead-domains-linter -i formatted_subdomains_file.tmp --export dead.tmp  # Find and export dead domains with subdomains
    [[ ! -s dead.tmp ]] && return  # Return if no dead domains found
    # Remove dead subdomains from subdomains file
    comm -23 "$subdomains_file" dead.tmp > subdomains.tmp && mv subdomains.tmp "$subdomains_file"
    cat dead.tmp >> "$dead_domains_file"  # Collate dead domains with subdomains to filter out from newly retrieved domains
    format_list "$dead_domains_file"

    while read -r subdomain; do  # Loop through common subdomains
        dead_root_domains=$(sed "s/^${subdomain}\.//" dead.tmp | sort -u)  # Strip to root domains
    done < "$subdomains_to_remove_file"
    # Remove dead root domains from raw file and root domains file
    comm -23 "$raw_file" <(printf "%s" "$dead_root_domains") > raw.tmp && mv raw.tmp "$raw_file"
    comm -23 "$root_domains_file" <(printf "%s" "$dead_root_domains") > root.tmp && mv root.tmp "$root_domains_file"
    log_event "$dead_root_domains" "dead" "raw"
}

function check_redundant {
    sed 's/^/||/; s/$/^/' "$redundant_domains_file" > formatted_redundant_domains_file.tmp  # Format redundant domains file
    dead-domains-linter -i formatted_redundant_domains_file.tmp --export dead.tmp  # Find and export dead redundant domains
    [[ ! -s dead.tmp ]] && return  # Return if no dead domains found
    # Remove dead redundant domains from redundant domains file
    comm -23 "$redundant_domains_file" dead.tmp > redundant.tmp && mv redundant.tmp "$redundant_domains_file"
    cat dead.tmp >> "$dead_domains_file"  # Collate dead redundant domains to filter out from newly retrieved domains
    format_list "$dead_domains_file"

    while read -r wildcard; do  # Loop through wildcards
        # If no matches remaining, consider wildcard as dead
        ! grep -q "\.${wildcard}$" "$redundant_domains_file" && printf "%s\n" "$wildcard" >> collated_dead_wildcards.tmp
    done < "$wildcards_file"
    [[ ! -f collated_dead_wildcards.tmp ]] && return  # Return if no unused wildcards found
    sort -u collated_dead_wildcards.tmp -o collated_dead_wildcards.tmp
    # Remove unused wildcards from raw file and wildcards file
    comm -23 "$raw_file" collated_dead_wildcards.tmp > raw.tmp && mv raw.tmp "$raw_file"
    comm -23 "$wildcards_file" collated_dead_wildcards.tmp > wildcards.tmp && mv wildcards.tmp "$wildcards_file"
    log_event "$(<collated_dead_wildcards.tmp)" "dead" "wildcard"
}

function check_for_dead {
    comm -23 "$raw_file" <(sort "$root_domains_file" "$wildcards_file") |  # Exclude wildcards and root domains of subdomains
        sed 's/^/||/; s/$/^/' > formatted_raw_file.tmp  # Format raw file
    dead-domains-linter -i formatted_raw_file.tmp --export dead.tmp  # Find and export dead domains
    [[ ! -s dead.tmp ]] && return  # Return if no dead domains found
    # Remove dead domains from raw file
    comm -23 "$raw_file" dead.tmp > raw.tmp && mv raw.tmp "$raw_file"
    cat dead.tmp >> "$dead_domains_file"  # Collate dead domains
    format_list "$dead_domains_file"
    log_event "$(<dead.tmp)" "dead" "raw"
}

function update_light_file {
    comm -12 "$raw_file" "$raw_light_file" > light.tmp && mv light.tmp "$raw_light_file"  # Keep only domains found in full raw file
}

function clean_dead_domains_file {
    [[ $(wc -l < "$dead_domains_file") -gt 5000 ]] && sed -i '1,100d' "$dead_domains_file" || printf ""  # printf to negate exit status 1
}

function log_event {
    # Log domain events
    printf "%s\n" "$1" | awk -v type="$2" -v source="$3" -v time="$time_format" '{print time "," type "," $0 "," source}' >> "$domain_log"
}

function format_list {
    bash data/tools.sh "format" "$1"
}

function cleanup {
    find . -maxdepth 1 -type f -name "*.tmp" -delete
    clean_dead_domains_file  # Clean dead domains file
}

trap cleanup EXIT
main

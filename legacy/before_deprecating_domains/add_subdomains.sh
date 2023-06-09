#!/bin/bash

raw_file="data/raw.txt"
subdomains_file="data/subdomains.txt"
dead_domains_file="data/dead_domains.txt"

trap "find . -maxdepth 1 -type f -name '*.tmp' -delete" EXIT

while read -r subdomain; do
    grep "^${subdomain}\." "$raw_file" >> only_subdomains.tmp
done < "$subdomains_file"

comm -23 "$raw_file" only_subdomains.tmp > second_level_domains.tmp

function check_resolving() {
    > alive.tmp
    
    echo -e "\nLog:"

    cat "$1" | xargs -I{} -P6 bash -c '
        domain="$1"
        while true; do
            dig=$(dig @1.1.1.1 "$domain")
            [[ "$dig" =~ error|timed\ out ]] || break
            echo "$domain timed out."
            sleep 1
        done
        if ! [[ "$dig" == *"NXDOMAIN"* ]]; then
            echo "$domain (alive)"
            echo "$domain" >> alive.tmp
        fi
    ' -- {}
}

function add_subdomains_to_wildcards {
    echo -e "\nFinding domains with a wildcard record..."
    
    random_subdomain='6nd7p7ccay6r5da'

    awk -v subdomain="$random_subdomain" '{print subdomain"."$0}' second_level_domains.tmp \
        > random_subdomain.tmp

    check_resolving random_subdomain.tmp

    awk -v subdomain="$random_subdomain" '{sub("^"subdomain"\\.", ""); print}' alive.tmp \
        > wildcards.tmp

    # Create a file with no wildcard domains. This file is sorted 
    grep -vxFf wildcards.tmp second_level_domains.tmp > no_wildcards.tmp

    [[ -s wildcards.tmp ]] || return

    awk '{print "www."$0}' wildcards.tmp > wildcards_with_www.tmp

    awk '{print "m."$0}' wildcards.tmp > wildcards_with_m.tmp

    cat wildcards_with_www.tmp >> new_domains.tmp

    cat wildcards_with_m.tmp >> new_domains.tmp
}

function add_subdomains {
    echo -e "\nChecking for resolving subdomains..."
    
    while read -r subdomain; do
        # Append the current subdomain in the loop to the domains
        awk -v subdomain="$subdomain" '{print subdomain"."$0}' no_wildcards.tmp > 1.tmp

        comm -23 1.tmp "$raw_file" > 2.tmp

        comm -23 2.tmp "$dead_domains_file" > 3.tmp
    
        grep -vxFf new_domains.tmp 3.tmp > subdomains.tmp

        check_resolving subdomains.tmp

        [[ -s alive.tmp ]] || continue

        cat alive.tmp >> new_domains.tmp
    done < "$subdomains_file"
}

add_subdomains_to_wildcards

add_subdomains

sort -u new_domains.tmp -o new_domains.tmp

comm -23 new_domains.tmp "$raw_file" > unique_domains.tmp

if ! [[ -s unique_domains.tmp ]]; then
    echo -e "\nNo domains added.\n"
    exit 0
fi

echo -e "\nAll domains added:"
cat unique_domains.tmp

echo -e "\nTotal domains added: $(wc -l < unique_domains.tmp)\n"

cat unique_domains.tmp >> "$raw_file"

sort "$raw_file" -o "$raw_file"

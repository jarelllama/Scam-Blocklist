#!/bin/bash
raw_file='data/raw.txt'
domain_log='data/domain_log.csv'
blacklist_file='config/blacklist.txt'
root_domains_file='data/processing/root_domains.txt'
subdomains_file='data/processing/subdomains.txt'
wildcards_file='data/processing/wildcards.txt'
redundant_domains_file='data/processing/redundant_domains.txt'
time_format="$(TZ=Asia/Singapore date +"%H:%M:%S %d-%m-%y")"

[[ "$CI" != true ]] && exit  # Do not allow running locally

function main {
    error=false  # Initilize error variable
    prepare_sample  # Prepare sample files
    bash retrieve.sh  # Run retrieval script
    printf "%s\n" "---------------------------------------------------------------------"
    printf "Run completed.\n"

    # Check returned error code
    if [[ "$?" -eq 1 ]]; then
        printf "! Script returned an error.\n"
        error=true
    fi
    # Check raw file
    if cmp -s "$raw_file" output.txt; then
        printf "Raw file is as expected.\n"
    else
        printf "! Raw file is not as expected:\n"
        cat "$raw_file"
        printf "\n"
        error=true
    fi
    # Check wildcards file
    if ! grep -q 'to.block.1.com' "$wildcards_file" &&  grep -q 'to.block.2.com' "$wildcards_file" &&
        grep -q 'to.block.3.com' "$wildcards_file" && grep -q 'to.block.4.com' "$wildcards_file"; then

        printf "! Wildcards file is incorrect:\n"
        cat "$wildcards_file"
        printf "\n"
        error=true
    fi
    # Check redundant domains file
    if ! grep -q 'match.wildcard.in.blocklist.com' "$redundant_domains_file" && grep -q 'also.match.wildcard.in.blocklist.com' "$redundant_domains_file"; then
        printf "! Redundant domains file is incorrect:\n"
        cat "$redundant_domains_file"
        printf "\n"
        error=true
    fi
    # Check root domains file
    if ! grep -q 'to.block1.com' "$root_domains_file" && grep -q 'to.block2.com' "$root_domains_file" &&
        grep -q 'to.block3.com' "$root_domains_file" && grep -q 'to.block4.com' "$root_domains_file"; then

        printf "! Root domains file is incorrect:\n"
        cat "$root_domains_file"
        printf "\n"
        error=true
    fi
    # Check subdomains file
    if ! grep -q 'www.to.block1.com' "$root_domains_file" && grep -q 'm.block1.com' "$root_domains_file" &&
        grep -q 'shop.to.block3.com' "$root_domains_file" && grep -q 'store.to.block4.com' "$root_domains_file"; then

        printf "! Subdomains file is incorrect:\n"
        cat "$subdomains_file"
        printf "\n"
        error=true
    fi

    printf "Log:\n"
    grep "$time_format" "$domain_log"  # Print log
    printf "%s\n" "---------------------------------------------------------------------"

    [[ "$error" == true ]] && exit 1 || exit 0  # Exit with error if script did not run as intended
}

function prepare_sample {
    printf "in.blocklist.com\n" > "$raw_file"  # Prepare sample raw file
    printf "wildcard.in.blocklist.com\n" >> "$raw_file"
    printf "wildcard.in.blocklist.com\n" > "$wildcards_file"  # Prepare sample wildcards file
    printf "blacklisted.forum.com\n" > "$blacklist_file"  # Prepare sample blacklist file

    cat << EOF > input.txt  # Prepare sample input data
www.to.block1.com
forum1.com
match.wildcard.in.blocklist.com
m.to.block2.com
forum2.com
also.match.wildcard.in.blocklist.com
shop.to.block3.com
blacklisted.forum.com
store.to.block4.com
blacklisted_forum.com
to.block5.com
to.block1.com
whitelisted.tld.mil
to.block2.com
whitelisted.tld.gov
to.block6.com
whitelisted.tld.edu
to.block7.com
whitelisted_forum.com
to.block8.com
EOF

    cat << EOF > output.txt  # Prepare expected result
blacklisted.forum.com
in.blocklist.com
to.block1.com
to.block2.com
to.block3.com
to.block4.com
to.block5.com
to.block6.com
to.block7.com
to.block8.com
wildcard.in.blocklist.com
EOF

    split -n l/7 input.txt  # Split the domains
    mv xaa data/domains_aa419.tmp
    mv xab data/domains_guntab.tmp
    mv xac data/domains_petscams.tmp
    mv xad data/domains_google_search_test_search_term.tmp
    mv xae data/domains_stopgunscams.tmp
    mv xaf data/domains_scamdelivery.tmp
    mv xag data/domains_scamdirectory.tmp
    mv xah data/domains_scamadviser.tmp
}

main

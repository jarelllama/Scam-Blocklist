#!/bin/bash
raw_file='data/raw.txt'
wildcards_file='data/wildcards.txt'
blacklist_file='config/blacklist.txt'
domain_log='data/domain_log.csv'

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
        check_raw_file
        error=true
    fi
    # Check raw file
    if cmp -s "$raw_file" output.tmp; then
        printf "Raw file is as expected.\n"
    else
        printf "! Raw file is not as expected:\n"
        cat "$raw_file"
        printf "\n"
        error=true
    fi
    # Check wildcards file
    if ! grep -q 'to.block.1.com' "$wildcards_file" && grep -q 'to.block.2.com' "$wildcards_file"; then
        printf "! Wildcards file is incorrect:\n"
        cat "$wildcards_file"
        printf "\n"
        error=true
    fi

    printf "Log:\n"
    tail -9 "$domain_log"
    printf "%s\n" "---------------------------------------------------------------------"

    [[ "$error" == true ]] && exit 1 || exit 0  # Exit with error if script did not run as intended
}

function prepare_sample {
    printf "in.blocklist.com\n" > "$raw_file"  # Prepare sample raw file
    printf "wildcard.in.blocklist.com\n" >> "$raw_file"
    printf "wildcard.in.blocklist.com\n" > "$wildcards_file"  # Prepare sample wildcards file
    printf "blacklisted.forum.com\n" > "$blacklist_file"  # Prepare sample blacklist file

    cat << EOF > input.tmp  # Prepare sample input data
also.match.wildcaard.in.blocklist.com
blacklisted.forum.com
in.blocklist.com
m.to.block.1.com
match.wildcard.in.blocklist.com
to.block.1.com
to.block.3.com
to.block.4.com
whitelisted.forum.com
whitelisted.tld.gov
wildcard.in.blocklist.com
www.to.block.2.com
EOF

    cat << EOF > output.tmp  # Prepare expected result
blacklisted.forum.com
in.blocklist.com
to.block.1.com
to.block.2.com
to.block.3.com
to.block.4.com
wildcard.in.blocklist.com
EOF

    split -n l/4 input.tmp  # Split the 10 domains into 3 source files
    mv xaa data/domains_aa419.tmp
    mv xab data/domains_guntab.tmp
    mv xac data/domains_petscams.tmp
    mv xad data/domains_google_search_test_search_term.tmp
}

main

#!/bin/bash
raw_file='data/raw.txt'
wildcards_file='data/wildcards.txt'
blacklist_file='config/blacklist.txt'

[[ "$CI" != true ]] && exit  # Do not allow running locally

function main {
    prepare_sample  # Prepare sample files
    bash retrieve.sh  # Run retrieval script
    printf "%s\n" "---------------------------------------------------------------------"
    printf "Run completed.\n"

    # Check returned error code
    if [[ "$?" -eq 1 ]]; then
        printf "! Script returned an error.\n"
        check_raw_file
        exit 1
    fi
    check_raw_file
}

function check_raw_file {
    if cmp -s "$raw_file" output.tmp; then
        printf "Raw file is as expected.\n"
        check_wildcards_file
        return
    fi
    printf "! Raw file is not as expected:\n"
    cat "$raw_file"
    printf "\n"
    check_wildcards_file
    exit 1
}

function check_wildcards_file {
    if grep -q 'to.block.1.com' "$wildcards_file" && grep -q 'to.block.2.com' "$wildcards_file"; then
        return
    fi
    printf "! Wildcards file is incorrect.\n"
    cat "$wildcards_file"
    exit 1
}

function prepare_sample {
    printf "in.blocklist.com\n" > "$raw_file"  # Prepare sample raw file
    printf "wildcard.in.blocklist.com\n" >> "$raw_file"
    printf "wildcard.in.blocklist.com\n" > "$wildcards_file"  # Prepare sample wildcards file
    printf "blacklisted.forum.com\n" > "$blacklist_file"  # Prepare sample blacklist file

    cat << EOF > input.tmp  # Prepare sample input data
blacklisted.forum.com
in.blocklist.com
m.to.block.1.com
match.wildcard.in.blocklist.com
to.block.1.com
to.block.3.com
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
wildcard.in.blocklist.com
EOF

    split -n l/3 input.tmp  # Split the 10 domains into 3 source files
    mv xaa data/domains_aa419.tmp
    mv xab data/domains_google_search_test_search_term_1.tmp
    mv xac data/domains_google_search_test_search_term_2.tmp
}

main

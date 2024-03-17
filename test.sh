#!/bin/bash
raw_file='data/raw.txt'
wildcards_file='data/wildcards.txt'
blacklist_file='data/blacklist.txt'

[[ "$CI" != true ]] && exit  # Do not allow running locally

function main {
    prepare_sample  # Prepare sample files

    bash retrieve.sh  # Run retrieval script
    # Check returned error code
    if [[ "$?" -eq 1 ]]; then
        printf "Script returned an error\n\n"
        check_output
        exit 1
    fi
    check_output
}

function check_output {
    # Check script output
    if cmp -s "$raw_file" output.tmp; then
        printf "Output is as expected.\n\n"
        return
    fi
    printf "Output is not as expected:\n\n"
    cat "$raw_file"
    printf "\n"
    exit 1
}

function prepare_sample {
    printf "in.blocklist.com" > "$raw_file"  # Prepare sample raw file
    printf "wildcard.in.blocklist.com" >> "$raw_file"
    printf "wildcard.in.blocklist.com" > "$wildcards_file"  # Prepare sample wildcards file
    printf "blacklisted.forum.com" > "$blacklist_file"  # Prepare sample blacklist file

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
#!/bin/bash
raw_file='data/raw.txt'
domain_log='data/domain_log.csv'
whitelist_file='config/whitelist.txt'
blacklist_file='config/blacklist.txt'
root_domains_file='data/processing/root_domains.txt'
subdomains_file='data/processing/subdomains.txt'
subdomains_to_remove_file='config/subdomains.txt'
wildcards_file='data/processing/wildcards.txt'
redundant_domains_file='data/processing/redundant_domains.txt'
dead_domains_file='data/processing/dead_domains.txt'
time_format="$(TZ=Asia/Singapore date +"%H:%M:%S %d-%m-%y")"

[[ "$CI" != true ]] && exit  # Do not allow running locally

function main {
    error=false  # Initialize error variable
    errored=false  # Initialize whether script returned with error
    : > "$raw_file"  # Initialize raw file

    # Do not run when there are existing domain files
    if [[ "$1" == 'retrieval' ]] && ! ls data/domains_*.tmp &> /dev/null; then
        test_retrieval_maintainence "$1"
    fi
    [[ "$1" == 'maintain' ]] && test_retrieval_maintainence "$1"
    [[ "$1" == 'dead' ]] && test_dead
}

function test_retrieval_maintainence {
    script_to_test="$1"

    # Test removal of common subdomains
    : > "$subdomains_file"  # Initialize subdomains file
    : > "$root_domains_file"  # Initialize root domains file
    while read -r subdomain; do
        subdomain="${subdomain}.subdomain-test.com" 
        printf "%s\n" "$subdomain" >> input.txt  # Add subdomain to input file
        printf "%s\n" "$subdomain" >> out_subdomains.txt  # Add subdomain to expected subdomains file
    done < "$subdomains_to_remove_file"
    printf "subdomain-test.com\n" >> out_raw.txt  # Add expected result to expected raw file
    printf "subdomain-test.com\n" >> out_root_domains.txt  # Add expected result to root domains file

    if [[ "$script_to_test" == 'retrieval' ]]; then
        # Test removal of domains already in blocklist
        printf "in-blocklist-test.com\n" >> "$raw_file"  # Add test domain to raw file
        printf "in-blocklist-test.com\n" >> input.txt

        # Test removal of known dead domains
        printf "dead-test.com\n" > "$dead_domains_file"  # Add test domain to dead domains file
        printf "dead-test.com\n" >> input.txt 
    fi

    # Test removal of whitelisted domains and blacklist exclusion
    printf "whitelist\n" > "$whitelist_file"  # Add test whitelist term to whitelist file
    printf "whitelist-blacklisted-test.com\n" > "$blacklist_file"  # Add test blacklisted domain to blacklist file
    printf "whitelist-test.com\n" >> input.txt
    printf "whitelist-blacklisted-test.com\n" >> input.txt
    printf "whitelist-blacklisted-test.com\n" >> out_raw.txt  # Add expected result to expected raw file

    # Test removal of domains with whitelisted TLDs
    {
        printf "whitelisted-tld-test.gov\n"
        printf "whitelisted-tld-test.edu\n"
        printf "whitelisted-tld-test.mil\n" 
    } >> input.txt

    # Skip IP address removal since it returns an error code of 1

    # Test removal of redundant domains
    : > "$redundant_domains_file"  # Initialize redundant domains file
    printf "redundant-test.com\n" > "$wildcards_file"  # Add test wildcard to wildcards file
    printf "domain.redundant-test.com\n" >> input.txt
    printf "domain.redundant-test.com\n" >> out_redundant.txt  # Add expected result to redundant domains file
    if [[ "$script_to_test" == 'maintain' ]]; then
        : > "$wildcards_file"  # Initialize wildcards file for maintainence script test
        printf "redundant-test.com\n" >> input.txt  # Add test wildcard to input file
        printf "redundant-test.com\n" >> out_wildcards.txt  # Add expected result to wildcards file
    fi

    # Skip toplist test since it returns an error code of 1

    # Prepare expected output files
    for file in out_*; do
        sort "$file" -o "$file"
    done

    if [[ "$script_to_test" == 'retrieval' ]]; then
        # Distribute the sample input domains into 3 files
        split -n l/3 input.txt
        mv xaa data/domains_aa419.tmp
        mv xab data/domains_google_search_search-term-1.tmp
        mv xac data/domains_google_search_search-term-2.tmp
        
        bash retrieve.sh  # Run retrievel script
        [[ "$?" -eq 1 ]] && errored=true  # Check returned error code
    fi

    if [[ "$script_to_test" == 'maintain' ]]; then
        mv input.txt "$raw_file"  # Prepare sample raw file
        bash maintain.sh || true  # Run maintainence script and ignore returned exit code
    fi
    
    printf "%s\n" "---------------------------------------------------------------------"
    printf "Run completed.\n"

    # Check returned error code
    if [[ "$errored" == true ]]; then
        printf "! Script returned an error.\n"
        error=true
    fi
    # Check raw file
    check_output "$raw_file" "out_raw.txt" "Raw"
    # Check subdomains file
    check_output "$subdomains_file" "out_subdomains.txt" "Subdomains"
    # Check root domains file
    check_output "$root_domains_file" "out_root_domains.txt" "Root domains"
    # Check redundant domains file
    check_output "$redundant_domains_file" "out_redundant.txt" "Redundant domains"
    # Check wildcards file
    [[ "$script_to_test" == 'maintain' ]] && check_output "$wildcards_file" "out_wildcards.txt" "Wildcards"

    printf "Log:\n"
    grep "$time_format" "$domain_log"  # Print log
    printf "%s\n" "---------------------------------------------------------------------"
    [[ "$error" == true ]] && exit 1 || exit 0  # Exit with error if test failed
}

function test_dead {
    # Test addition of resurrected domains
    printf "google.com\n" > "$dead_domains_file"  # Add test domain to dead domains file
    printf "google.com\n" >> out_raw.txt  # Add expected result to expected raw file

    # Test removal of dead domains with subdomains
    : > "$subdomains_file"  # Initialize subdomains file 
    printf "584308-dead-subdomain-test.com\n" >> "$raw_file"  # Add test dead root domain to raw file
    printf "584308-dead-subdomain-test.com\n" > "$root_domains_file"  # Add test dead root domain to root domains file
    while read -r subdomain; do
        subdomain="${subdomain}.584308-dead-subdomain-test.com" 
        printf "%s\n" "$subdomain" >> "$subdomains_file"  # Add test dead subdomain to subdomains flie
        printf "%s\n" "$subdomain" >> out_dead.txt  # Add expected result to dead domains flie
    done < "$subdomains_to_remove_file"

    # Test removal of dead redundant domains and wildcards
    printf "493053dead-wildcard-test.com\n" >> "$raw_file"  # Add test dead wildcard to raw file
    printf "493053dead-wildcard-test.com\n" > "$wildcards_file"  # Add test dead wildcard to wildcards file
    {
        printf "redundant-1.493053dead-wildcard-test.com\n"
        printf "redundant-2.493053dead-wildcard-test.com\n"
    } >> "$redundant_domains_file"  # Add test dead redundant domain to raw file
    {
        printf "redundant-1.493053dead-wildcard-test.com\n"
        printf "redundant-2.493053dead-wildcard-test.com\n"
    } >> out_dead.txt  # Add expected results to dead domains file

    # Check removal of dead domains
    printf "49532dead-domain-test.com\n" >> "$raw_file"  # Add test dead domain to dead domains file
    printf "49532dead-domain-test.com\n" >> out_dead.txt  # Add expected result to dead domains file

    # Prepare expected output files
    for file in out_*; do
        sort "$file" -o "$file"
    done

    bash dead.sh  # Run dead script
    [[ "$?" -eq 1 ]] && errored=true  # Check returned error code
    printf "%s\n" "---------------------------------------------------------------------"
    printf "Run completed.\n"

    # Check returned error code
    if [[ "$errored" == true ]]; then
        printf "! Script returned an error.\n"
        error=true
    fi
    # Check raw file
    check_output "$raw_file" "out_raw.txt" "Raw"
    # Check dead domains file
    check_output "$dead_domains_file" "out_dead.txt" "Dead domains"
    # Check subdomains file
    check_if_dead_present "$subdomains_file" "Subdomains"
    # Check root domains file
    check_if_dead_present "$root_domains_file" "Root domains"
    # Check redundant domains file
    check_if_dead_present "$redundant_domains_file" "Redundant domains"
    # Check wildcards file
    check_if_dead_present "$wildcards_file" "Wildcards"

    printf "Log:\n"
    grep "$time_format" "$domain_log"  # Print log
    printf "%s\n" "---------------------------------------------------------------------"
    [[ "$error" == true ]] && exit 1 || exit 0  # Exit with error if test failed
}

function check_output {
    if ! cmp -s "$1" "$2"; then
        printf "! %s file is not as expected:\n" "$3"
        cat "$1"
        printf "\n"
        printf "Expected output:\n"
        cat "$2"
        printf "\n"
        error=true
    else
        [[ "$1" == "$raw_file" ]] && printf "Raw file is as expected.\n"
    fi
}

function check_if_dead_present {
    if grep -q '[[:alpha:]]' "$1"; then
        printf "! %s file still has dead domains:\n" "$2"
        cat "$1"
        printf "\n"
        error=true
    fi
}

main "$1"

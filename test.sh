#!/bin/bash
raw_file='data/raw.txt'
domain_log='config/domain_log.csv'
whitelist_file='config/whitelist.txt'
blacklist_file='config/blacklist.txt'
parked_domains_file='data/parked_domains.txt'
root_domains_file='data/root_domains.txt'
subdomains_file='data/subdomains.txt'
subdomains_to_remove_file='config/subdomains.txt'
wildcards_file='data/wildcards.txt'
redundant_domains_file='data/redundant_domains.txt'
dead_domains_file='data/dead_domains.txt'

[[ "$CI" != true ]] && exit  # Do not allow running locally

function main {
    error=false  # Initialize error variable
    errored=false  # Initialize whether script returned with error
    log_error=false  # Initialize whether log file has an error
    : > "$raw_file"  # Initialize raw file
    sed '1q' "$domain_log" > log.tmp && mv log.tmp "$domain_log"  # Intialize domain log file

    # Do not run when there are existing domain files
    if [[ "$1" == 'retrieval' ]] && [[ ! -d data/pending ]]; then
        test_retrieval_check "$1"
    fi
    [[ "$1" == 'check' ]] && test_retrieval_check "$1"
    [[ "$1" == 'dead' ]] && test_dead || exit 0  # Return 0 if no tests were done
}

function test_retrieval_check {
    script_to_test="$1"

    # Test removal of common subdomains
    : > "$subdomains_file"  # Initialize subdomains file
    : > "$root_domains_file"  # Initialize root domains file
    while read -r subdomain; do
        subdomain="${subdomain}.subdomain-test.com"
        printf "%s\n" "$subdomain" >> input.txt  # Input
        printf "%s\n" "$subdomain" >> out_subdomains.txt  # Expected output
        grep -v 'www.' <(printf "subdomain,%s" "$subdomain") >> out_log.txt  # Expected output
    done < "$subdomains_to_remove_file"
    # Expected output
    [[ "$script_to_test" == 'check' ]] && printf "subdomain,www.subdomain-test.com\n" >> out_log.txt  # Check script does not exclude 'www' subdomains
    printf "subdomain-test.com\n" >> out_raw.txt
    printf "subdomain-test.com\n" >> out_root_domains.txt

    if [[ "$script_to_test" == 'retrieval' ]]; then
        # Test removal of domains already in blocklist
        printf "in-blocklist-test.com\n" >> "$raw_file"  # Sample data
        printf "in-blocklist-test.com\n" >> out_raw.txt  # Domain should already be present in expected raw file
        printf "in-blocklist-test.com\n" >> input.txt  # Input

        # Test removal of known dead domains
        printf "dead-test.com\n" > "$dead_domains_file"  # Sample data
        printf "dead-test.com\n" >> input.txt  # Input
        
        # No expected output for both tests
    fi

    # Test removal of whitelisted domains and blacklist exclusion
    # Sample data
    printf "whitelist\n" > "$whitelist_file"
    printf "whitelist-blacklisted-test.com\n" > "$blacklist_file"
    # Input
    printf "whitelist-test.com\n" >> input.txt
    printf "whitelist-blacklisted-test.com\n" >> input.txt
    # Expected output
    printf "whitelist-blacklisted-test.com\n" >> out_raw.txt
    printf "whitelist,whitelist-test.com\n" >> out_log.txt
    [[ "$script_to_test" == 'retrieve' ]] && printf "blacklist,whitelist-blacklisted-test.com\n" \
        >> out_log.txt  # Check script does not log blacklisted domains

    # Test removal of domains with whitelisted TLDs
    {
        printf "white-tld-test.gov\n"
        printf "white-tld-test.edu\n"
        printf "white-tld-test.mil\n"
    } >> input.txt  # Input
    {
        printf "tld,white-tld-test.gov\n"
        printf "tld,white-tld-test.edu\n"
        printf "tld,white-tld-test.mil\n"
    } >> out_log.txt  # Expected output

    # Test removal of invalid entries and IP addresses
    {
        printf "invalid-test-com\n"
        printf "100.100.100.100\n"
        printf "invalid-test.xn--903fds\n"
        printf "invalid-test.x\n"
        printf "invalid-test.100\n"
        printf "invalid-test.1x\n"
    } >> input.txt  # Input
    printf "invalid-test.xn--903fds\n" >> out_raw.txt
    {
        printf "invalid,invalid-test-com\n"
        printf "invalid,100.100.100.100\n"
        printf "invalid,invalid-test.x\n"
        printf "invalid,invalid-test.100\n"
        printf "invalid,invalid-test.1x\n"
    } >> out_log.txt  # Expected output

    # Test removal of redundant domains
    : > "$redundant_domains_file"  # Initialize redundant domains file
    printf "redundant-test.com\n" > "$wildcards_file"  # Sample data
    printf "domain.redundant-test.com\n" >> input.txt  # Input
    # No expected output for retrieval script test
    if [[ "$script_to_test" == 'check' ]]; then
        : > "$wildcards_file"  # Initialize wildcards file
        printf "redundant-test.com\n" >> input.txt  # Input
        printf "redundant-test.com\n" >> out_raw.txt  # Wildcard should already be present in expected raw file
        # Expected output
        printf "redundant-test.com\n" >> out_wildcards.txt
        printf "domain.redundant-test.com\n" >> out_redundant.txt
        printf "redundant,domain.redundant-test.com\n" >> out_log.txt
    fi

    # Skip toplist test since it prevents the changes from being saved to the raw file

    # Prepare expected output files
    for file in out_*; do
        sort "$file" -o "$file"
    done

    if [[ "$script_to_test" == 'retrieval' ]]; then
        # Distribute the sample input into 3 files
        mkdir data/pending
        split -n l/3 input.txt
        mv xaa data/pending/domains_aa419.org.tmp
        mv xab data/pending/domains_google_search_search-term-1.tmp
        mv xac data/pending/domains_google_search_search-term-2.tmp
        bash retrieve.sh || true  # Run retrievel script and ignore returned exit code
    elif [[ "$script_to_test" == 'check' ]]; then
        mv input.txt "$raw_file"  # Prepare sample raw file
        bash check.sh || true  # Run lists check script and ignore returned exit code
    fi
    printf "%s\n" "---------------------------------------------------------------------"

    check_output "$raw_file" "out_raw.txt" "Raw"  # Check raw file
    check_output "$subdomains_file" "out_subdomains.txt" "Subdomains"  # Check subdomains file
    check_output "$root_domains_file" "out_root_domains.txt" "Root domains"  # Check root domains file
    if [[ "$script_to_test" == 'check' ]]; then
        check_output "$redundant_domains_file" "out_redundant.txt" "Redundant domains"  # Check redundant domains file
        check_output "$wildcards_file" "out_wildcards.txt" "Wildcards"  # Check wildcards file
    fi
    check_log  # Check log file

    [[ "$error" == false ]] && printf "Test completed. No errors found.\n\n"
    [[ "$log_error" == false ]] && printf "Log:\n%s\n" "$(<$domain_log)"
    printf "%s\n" "---------------------------------------------------------------------"
    [[ "$error" == true ]] && exit 1 || exit 0  # Exit with error if test failed
}

function test_dead {
    # Test addition of resurrected domains
    # Input
    printf "google.com\n" > "$dead_domains_file"
    printf "584031dead-domain-test.com\n" >> "$dead_domains_file"
    # Expected output
    printf "google.com\n" >> out_raw.txt
    printf "584031dead-domain-test.com\n" >> out_dead.txt
    printf "resurrected,google.com,dead_domains_file\n" >> out_log.txt

    # Test removal of dead domains with subdomains
    : > "$subdomains_file"  # Initialize subdomains file
    printf "584308-dead-subdomain-test.com\n" >> "$raw_file"  # Input
    printf "584308-dead-subdomain-test.com\n" > "$root_domains_file"  # Input
    while read -r subdomain; do
        subdomain="${subdomain}.584308-dead-subdomain-test.com"
        printf "%s\n" "$subdomain" >> "$subdomains_file"  # Input
        printf "%s\n" "$subdomain" >> out_dead.txt  # Expected output
    done < "$subdomains_to_remove_file"
    printf "%s\n" "dead,584308-dead-subdomain-test.com,raw" >> out_log.txt  # Expected output

    # Test removal of dead redundant domains and wildcards
    : > "$redundant_domains_file"  # Initialize redundant domains file
    printf "493053dead-wildcard-test.com\n" >> "$raw_file"  # Input
    printf "493053dead-wildcard-test.com\n" > "$wildcards_file"  # Input
    {
        printf "redundant-1.493053dead-wildcard-test.com\n"
        printf "redundant-2.493053dead-wildcard-test.com\n"
    } >> "$redundant_domains_file"  # Input
    {
        printf "redundant-1.493053dead-wildcard-test.com\n"
        printf "redundant-2.493053dead-wildcard-test.com\n"
    } >> out_dead.txt  # Expected output
    {
        printf "dead,493053dead-wildcard-test.com,wildcard\n"
        printf "dead,493053dead-wildcard-test.com,wildcard\n"
    } >> out_log.txt # Expected output

    # Check removal of dead domains
    printf "49532dead-domain-test.com\n" >> "$raw_file"  # Input
    printf "49532dead-domain-test.com\n" >> out_dead.txt  # Expected output
    printf "dead,49532dead-domain-test.com,raw\n" >> out_log.txt  # Expected output

    # Test addition of unparked domains
    printf "apple.com\n" > "$parked_domains_file"  # Input
    printf "apple.com\n" >> out_raw.txt  # Expected output
    printf "unparked,apple.com,parked_domains_file\n" >> out_log.txt  # Expected output

    # Test removal of parked domains
    printf "ifansonly.com\n" >> "$raw_file"  # Input
    printf "ifansonly.com\n" > out_parked.txt  # Expected output
    printf "parked,ifansonly.com,raw\n" >> out_log.txt  # Expected output
    
    # Prepare expected output files
    for file in out_*; do
        [[ "$file" == out_dead.txt ]] && continue  # Dead domains file is not sorted
        sort "$file" -o "$file"
    done

    bash dead.sh  # Run dead script
    [[ "$?" -eq 1 ]] && errored=true  # Check returned error code
    printf "\n%s\n" "---------------------------------------------------------------------"

    # Check returned error code
    if [[ "$errored" == true ]]; then
        printf "! Script returned an error.\n"
        error=true
    fi
    check_output "$raw_file" "out_raw.txt" "Raw"  # Check raw file
    check_output "$dead_domains_file" "out_dead.txt" "Dead domains"  # Check dead domains file
    check_if_dead_present "$subdomains_file" "Subdomains"  # Check subdomains file
    check_if_dead_present "$root_domains_file" "Root domains"  # Check root domains file
    check_if_dead_present "$redundant_domains_file" "Redundant domains"  # Check redundant domains file
    check_if_dead_present "$wildcards_file" "Wildcards"  # Check wildcards file
    check_output "$parked_domains_file" "out_parked.txt" "Parked domains"  # Check parked domains file
    check_log  # Check log file

    [[ "$error" == false ]] && printf "Test completed. No errors found.\n" ||
        printf "The dead-domains-linter may have false positives. Rerun the job to confirm.\n"
    printf "%s\n" "---------------------------------------------------------------------"
    [[ "$error" == true ]] && exit 1 || exit 0  # Exit with error if test failed
}

function check_output {
    if cmp -s "$1" "$2"; then
        return
    fi
    printf "! %s file is not as expected:\n" "$3"
    cat "$1"
    printf "\nExpected output:\n"
    cat "$2"
    printf "\n"
    error=true
}

function check_if_dead_present {
    if ! grep -q '[[:alnum:]]' "$1"; then
        return
    fi
    printf "! %s file still has dead domains:\n" "$2"
    cat "$1"
    printf "\n"
    error=true
}

function check_log {
    log_error=false
    while read -r log_term; do
        if ! grep -qF "$log_term" "$domain_log"; then
            log_error=true
            break
        fi
    done < out_log.txt
    [[ "$log_error" == false ]] && return
    printf "! Log file is not as expected:\n"
    cat "$domain_log"
    printf "\nTerms expected in log:\n"
    cat out_log.txt  # No need for additional new line since the log is not printed again
    error=true
    }

main "$1"

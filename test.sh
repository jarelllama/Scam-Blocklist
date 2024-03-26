#!/bin/bash
raw_file='data/raw.txt'
raw_light_file='data/raw_light.txt'
domain_log='config/domain_log.csv'
whitelist_file='config/whitelist.txt'
blacklist_file='config/blacklist.txt'
root_domains_file='data/root_domains.txt'
subdomains_file='data/subdomains.txt'
subdomains_to_remove_file='config/subdomains.txt'
wildcards_file='data/wildcards.txt'
redundant_domains_file='data/redundant_domains.txt'
dead_domains_file='data/dead_domains.txt'

[[ "$CI" != true ]] && exit 1  # Do not allow running locally

function main {
    : > "$raw_file"  # Initialize raw file
    : > "$raw_light_file"  # Initialize raw light file
    sed -i '1q' "$domain_log"  # Initialize domain log file
    [[ "$1" == 'retrieval' ]] && [[ ! -d data/pending ]] && test_retrieval_check "$1"  # Do not run when there are existing domain files
    [[ "$1" == 'toplist' ]] && test_toplist
    [[ "$1" == 'check' ]] && test_retrieval_check "$1"
    [[ "$1" == 'dead' ]] && test_dead
    [[ "$1" == 'shellcheck' ]] && shellcheck
    exit 0
}

function shellcheck {
    # Download and run ShellCheck
    url='https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.linux.x86_64.tar.xz'
    wget -qO - "$url" | tar -xJ  # Download ShellCheck
    printf "%s\n" "$(shellcheck-stable/shellcheck --version)"
    scripts=$(find . ! -path "./legacy/*" -type f -name "*.sh")  # Find scripts
    while read -r script; do  # Loop through scripts
        shellcheck-stable/shellcheck "$script" || error=true  # Run ShellCheck for each script
    done <<< "$scripts"
    # Check for carriage return characters
    problematic_files=$(grep -rl $'\r' --exclude-dir={legacy,.git,shellcheck-stable} .)
    if [[ -n "$problematic_files" ]]; then
        printf "\nLines with carriage return characters:\n"
        printf "%s\n" "$problematic_files"
        error=true
    fi
    # Check for missing space before comments
    problematic_files=$(grep -rn '\S\s#' --exclude-dir={legacy,.git,shellcheck-stable} --exclude=*.csv .)
    if [[ -n "$problematic_files" ]]; then
        printf "\nLines with missing space before comments:\n"
        printf "%s\n" "$problematic_files"
        error=true
    fi
    printf "\nScripts checked (%s):\n%s\n" "$(wc -l <<< "$scripts")" "$scripts"
    check_error
}

function test_retrieval_check {
    script_to_test="$1"
    [[ "$script_to_test" == 'retrieval' ]] && mkdir data/pending

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
    [[ "$script_to_test" == 'check' ]] && printf "subdomain,www.subdomain-test.com\n" >> out_log.txt  # The Check script does not exclude 'www' subdomains
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
        >> out_log.txt  # The check script does not log blacklisted domains

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

    : > "$redundant_domains_file"  # Initialize redundant domains file
    if [[ "$script_to_test" == 'retrieval' ]]; then
        # Test removal of new redundant domains
        printf "redundant-test.com\n" > "$wildcards_file"  # Sample data
        printf "redundant-test.com\n" >> out_wildcards.txt  # Wildcard should already be in expected wildcards file
        printf "domain.redundant-test.com\n" >> input.txt  # Input
        printf "redundant,domain.redundant-test.com\n" >> out_log.txt  # Expected output
    elif [[ "$script_to_test" == 'check' ]]; then
        # Test addition of new wildcard from wildcard file
        printf "domain.redundant-test.com\n" >> input.txt  # Sample data
        printf "redundant-test.com\n" > "$wildcards_file"  # Input
        # Expected output
        printf "redundant-test.com\n" >> out_raw.txt
        printf "redundant-test.com\n" >> out_wildcards.txt
        printf "domain.redundant-test.com\n" >> out_redundant.txt
        printf "redundant,domain.redundant-test.com\n" >> out_log.txt  # Expected output
    fi

    if [[ "$script_to_test" == 'check' ]]; then
        # Test toplist check
        printf "google.com\n" >> input.txt  # Input
        printf "google.com\n" >> out_raw.txt  # Expected output
        printf "toplist,google.com\n" >> out_log.txt  # Expected output
    fi

    # Test light raw file exclusion of specific sources
    if [[ "$script_to_test" == 'retrieval' ]]; then
        cp "$raw_file" "$raw_light_file"  # Sample data
        printf "raw-light-test.com\n" > data/pending/domains_guntab.com.tmp  # Input
        cp out_raw.txt out_raw_light.txt  # Expected output
        printf "raw-light-test.com\n" >> out_raw.txt  # Expected output
    elif [[ "$script_to_test" == 'check' ]]; then
        cp out_raw.txt out_raw_light.txt  # Expected output
    fi

    # Prepare expected output files
    for file in out_*; do
        sort "$file" -o "$file"
    done

    if [[ "$script_to_test" == 'retrieval' ]]; then
        # Distribute the sample input into various sources
        split -n l/3 input.txt
        mv xaa data/pending/domains_aa419.org.tmp
        mv xab data/pending/domains_google_search_search-term-1.tmp
        mv xac data/pending/domains_google_search_search-term-2.tmp
        bash retrieve.sh || true  # Run retrieval script and ignore exit status
    elif [[ "$script_to_test" == 'check' ]]; then
        cp input.txt "$raw_file"  # Input
        mv input.txt "$raw_light_file"  # Input
        bash check.sh || true  # Run lists check script and ignore exit status
    fi
    printf "%s\n" "------------------------------------------------------------------"

    check_output "$raw_file" "out_raw.txt" "Raw"  # Check raw file
    check_output "$raw_light_file" "out_raw_light.txt" "Raw light"  # Check raw light file
    check_output "$subdomains_file" "out_subdomains.txt" "Subdomains"  # Check subdomains file
    check_output "$root_domains_file" "out_root_domains.txt" "Root domains"  # Check root domains file
    if [[ "$script_to_test" == 'retrieval' ]]; then
        [[ -d data/pending ]] && { printf "! Pending directory not removed.\n"; error=true; }  # Check pending directory
    elif [[ "$script_to_test" == 'check' ]]; then
        check_output "$redundant_domains_file" "out_redundant.txt" "Redundant domains"  # Check redundant domains file
        check_output "$wildcards_file" "out_wildcards.txt" "Wildcards"  # Check wildcards file
    fi
    check_log  # Check log file

    [[ "$error" != true ]] && printf "Test completed. No errors found.\n\n"
    [[ "$log_error" != true ]] && printf "Log:\n%s\n" "$(<$domain_log)"
    check_error
}

function test_toplist {
    mkdir data/pending
    : > "$whitelist_file"  # Sample data
    printf "google.com\n" > data/pending/domains_google_search_toplist-test.tmp  # Input
    printf "toplist,google.com\n" > out_log.txt  # Expected output
    bash retrieve.sh || true  # Run retrieval script and ignore exit status
    printf "%s\n" "------------------------------------------------------------------"
    [[ ! -d data/pending ]] && { printf "! Pending directory is missing.\n"; error=true; }  # Check pending directory
    check_log
    [[ "$error" != true ]] && printf "Test completed. No errors found.\n\n"
    check_error
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
    } >> out_log.txt  # Expected output

    # Check removal of dead domains
    printf "49532dead-domain-test.com\n" >> "$raw_file"  # Input
    printf "49532dead-domain-test.com\n" >> out_dead.txt  # Expected output
    printf "dead,49532dead-domain-test.com,raw\n" >> out_log.txt  # Expected output

    # Test raw light file
    cp "$raw_file" "$raw_light_file"  # Input
    grep -vF 'google.com' out_raw.txt > out_raw_light.txt  # Expected output (resurrected domains are not added back to light blocklist)

    # Prepare expected output files
    for file in out_*; do
        [[ "$file" != out_dead.txt ]] && sort "$file" -o "$file"  # Dead domains file is not sorted
    done

    bash dead.sh  # Run dead script
    [[ "$?" -eq 1 ]] && errored=true  # Check returned error code
    printf "%s\n" "------------------------------------------------------------------"

    [[ "$errored" == true ]] && { printf "! Script returned an error.\n"; error=true; }  # Check exit status
    check_output "$raw_file" "out_raw.txt" "Raw"  # Check raw file
    check_output "$raw_light_file" "out_raw_light.txt" "Raw light"  # Check raw light file
    check_output "$dead_domains_file" "out_dead.txt" "Dead domains"  # Check dead domains file
    check_if_dead_present "$subdomains_file" "Subdomains"  # Check subdomains file
    check_if_dead_present "$root_domains_file" "Root domains"  # Check root domains file
    check_if_dead_present "$redundant_domains_file" "Redundant domains"  # Check redundant domains file
    check_if_dead_present "$wildcards_file" "Wildcards"  # Check wildcards file
    check_log  # Check log file

    [[ "$error" != true ]] && printf "Test completed. No errors found.\n\n" ||
        printf "The dead-domains-linter may have false positives. Rerun the job to confirm.\n\n"
    [[ "$log_error" != true ]] && printf "Log:\n%s\n" "$(<$domain_log)"
    check_error
}

function check_output {
    cmp -s "$1" "$2" && return  # Return if files are the same
    printf "! %s file is not as expected:\n" "$3"
    cat "$1"
    printf "\nExpected output:\n"
    cat "$2"
    printf "\n"
    error=true
}

function check_if_dead_present {
    ! grep -q '[[:alnum:]]' "$1" && return  # Return if file has no domains
    printf "! %s file still has dead domains:\n" "$2"
    cat "$1"
    printf "\n"
    error=true
}

function check_log {
    while read -r log_term; do
        ! grep -qF "$log_term" "$domain_log" && { log_error=true; break; }  # Break when error found
    done < out_log.txt
    [[ "$log_error" != true ]] && return  # Return if no error found
    printf "! Log file is not as expected:\n"
    cat "$domain_log"
    printf "\nTerms expected in log:\n"
    cat out_log.txt  # No need for additional new line since the log is not printed again
    error=true
}

function check_error {
    [[ "$error" == true ]] && { printf "\n"; exit 1; }  # Exit with error if test failed
}

main "$1"

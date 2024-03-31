#!/bin/bash
# This script is used to test the various functions.

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly WHITELIST='config/whitelist.txt'
readonly BLACKLIST='config/blacklist.txt'
readonly TOPLIST='data/toplist.txt'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'
readonly WILDCARDS='data/wildcards.txt'
readonly REDUNDANT_DOMAINS='data/redundant_domains.txt'
readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly DOMAIN_LOG='config/domain_log.csv'

[[ "$CI" != true ]] && exit 1  # Do not allow running locally

function main {
    : > "$RAW"  # Initialize raw file
    sed -i '1q' "$DOMAIN_LOG"  # Initialize domain log file
    [[ "$1" == 'retrieve' ]] && test_retrieve_validate "$1"
    [[ "$1" == 'validate' ]] && test_retrieve_validate "$1"
    [[ "$1" == 'dead' ]] && test_dead_check
    [[ "$1" == 'parked' ]] && test_parked_check
    [[ "$1" == 'shellcheck' ]] && shellcheck
    exit 0
}

function shellcheck {
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
        printf "\n\e[1m[warn] Lines with carriage return characters:\e[0m\n"
        printf "%s\n" "$problematic_files"
        error=true
    fi

    # Check for missing space before comments
    problematic_files=$(grep -rn '\S\s#' --exclude-dir={legacy,.git,shellcheck-stable} --exclude=*.csv .)
    if [[ -n "$problematic_files" ]]; then
        printf "\n\e[1m[warn] Lines with missing space before comments:\e[0m\n"
        printf "%s\n" "$problematic_files"
        error=true
    fi

    printf "\n[info] Scripts checked (%s):\n%s\n" "$(wc -l <<< "$scripts")" "$scripts"
    [[ "$error" == true ]] && { printf "\n"; exit 1; }  # Exit with error if test failed
}

test_retrieve_validate() {
    script_to_test="$1"
    [[ -d data/pending ]] && rm -r data/pending  # Initialize pending directory
    [[ "$script_to_test" == 'retrieve' ]] && mkdir data/pending

    if [[ "$script_to_test" == 'retrieve' ]]; then
        # Test removal of known dead domains
        {
            printf "dead-test.com\n"
            printf "www.dead-test-2.com\n"
        } > "$DEAD_DOMAINS"  # Sample data
        {
            printf "dead-test.com\n"
            printf "www.dead-test-2.com\n"
        } >> input.txt  # Input
        # No expected output (dead domains check does not log)
    fi

    # Test removal of common subdomains
    : > "$SUBDOMAINS"  # Initialize subdomains file
    : > "$ROOT_DOMAINS"  # Initialize root domains file
    while read -r subdomain; do
        subdomain="${subdomain}.subdomain-test.com"
        printf "%s\n" "$subdomain" >> input.txt  # Input
        printf "%s\n" "$subdomain" >> out_subdomains.txt  # Expected output
        grep -v 'www.' <(printf "subdomain,%s" "$subdomain") >> out_log.txt  # Expected output
    done < "$SUBDOMAINS_TO_REMOVE"
    # Expected output
    [[ "$script_to_test" == 'validate' ]] && printf "subdomain,www.subdomain-test.com\n" >> out_log.txt  # The Check script does not exclude 'www' subdomains
    printf "subdomain-test.com\n" >> out_raw.txt
    printf "subdomain-test.com\n" >> out_root_domains.txt

    # Removal of domains already in raw file is redundant to test

    if [[ "$script_to_test" == 'retrieve' ]]; then
        # Test removal of known parked domains
        printf "parked-domains-test.com\n" > "$PARKED_DOMAINS"  # Sample data
        printf "parked-domains-test.com\n" >> input.txt  # Input
        printf "parked,parked-domains-test.com\n" >> out_log.txt  # Expected output
    fi

    # Test removal of whitelisted domains and blacklist exclusion
    # Sample data
    printf "whitelist\n" > "$WHITELIST"
    printf "whitelist-blacklisted-test.com\n" > "$BLACKLIST"
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
    printf "invalid-test.xn--903fds\n" >> out_raw.txt  # Expected output
    [[ "$script_to_test" == 'retrieve' ]] &&
        {
            printf "invalid-test-com\n"
            printf "100.100.100.100\n"
            printf "invalid-test.x\n"
            printf "invalid-test.100\n"
            printf "invalid-test.1x\n"
        } >> out_manual.txt  # Expected output
    {
        printf "invalid,invalid-test-com\n"
        printf "invalid,100.100.100.100\n"
        printf "invalid,invalid-test.x\n"
        printf "invalid,invalid-test.100\n"
        printf "invalid,invalid-test.1x\n"
    } >> out_log.txt  # Expected output

    : > "$REDUNDANT_DOMAINS"  # Initialize redundant domains file
    if [[ "$script_to_test" == 'retrieve' ]]; then
        # Test removal of new redundant domains
        printf "redundant-test.com\n" > "$WILDCARDS"  # Sample data
        printf "redundant-test.com\n" >> out_wildcards.txt  # Wildcard should already be in expected wildcards file
        printf "domain.redundant-test.com\n" >> input.txt  # Input
        printf "redundant,domain.redundant-test.com\n" >> out_log.txt  # Expected output
    elif [[ "$script_to_test" == 'validate' ]]; then
        # Test addition of new wildcard from wildcard file (manually adding a new wildcard to wildcards file)
        printf "domain.redundant-test.com\n" >> input.txt  # Sample data
        printf "redundant-test.com\n" > "$WILDCARDS"  # Input
        # Expected output
        printf "redundant-test.com\n" >> out_raw.txt
        printf "redundant-test.com\n" >> out_wildcards.txt
        printf "domain.redundant-test.com\n" >> out_redundant.txt
        printf "redundant,domain.redundant-test.com\n" >> out_log.txt
    fi

    # Test toplist check
    if [[ "$script_to_test" == 'validate' ]]; then
        printf "microsoft.com\n" >> input.txt  # Input
        printf "microsoft.com\n" >> out_raw.txt  # Expected output
    elif [[ "$script_to_test" == 'retrieve' ]]; then
        printf "microsoft.com\n" >> data/pending/domains_guntab.com.tmp  # Input
        # Expected output
        printf "microsoft.com\n" >> out_pending.txt
        printf "toplist,microsoft.com\n" >> out_log.txt
    fi

    # Test light raw file exclusion of specific sources
    if [[ "$script_to_test" == 'retrieve' ]]; then
        cp "$RAW" "$RAW_LIGHT"
        printf "raw-light-test.com\n" >> data/pending/domains_guntab.com.tmp  # Input
        printf "raw-light-test.com\n" >> out_raw.txt  # Expected output
        grep -vF "raw-light-test.com" out_raw.txt > out_raw_light.txt  # Expected output for light (source excluded from light)
    elif [[ "$script_to_test" == 'validate' ]]; then
        cp out_raw.txt out_raw_light.txt  # Expected output for light
    fi

    if [[ "$script_to_test" == 'retrieve' ]]; then
        # Distribute the sample input into various sources
        split -n l/3 input.txt
        mv xaa data/pending/domains_aa419.org.tmp
        mv xab data/pending/domains_google_search_search-term-1.tmp
        mv xac data/pending/domains_google_search_search-term-2.tmp
        run_script "retrieve_domains.sh" "exit 0"
    elif [[ "$script_to_test" == 'validate' ]]; then
        cp input.txt "$RAW"  # Input
        mv input.txt "$RAW_LIGHT"  # Input
        run_script "validate_raw.sh" "exit 0"
    fi

    check_output "$RAW" "out_raw.txt" "Raw"  # Check raw file
    check_output "$RAW_LIGHT" "out_raw_light.txt" "Raw light"  # Check raw light file
    check_output "$SUBDOMAINS" "out_subdomains.txt" "Subdomains"  # Check subdomains file
    check_output "$ROOT_DOMAINS" "out_root_domains.txt" "Root domains"  # Check root domains file
    if [[ "$script_to_test" == 'retrieve' ]]; then
        check_output "data/pending/domains_guntab.com.tmp" "out_pending.txt" "Manual review"  # Check manual review file
    elif [[ "$script_to_test" == 'validate' ]]; then
        check_output "$REDUNDANT_DOMAINS" "out_redundant.txt" "Redundant domains"  # Check redundant domains file
        check_output "$WILDCARDS" "out_wildcards.txt" "Wildcards"  # Check wildcards file
    fi
    check_log  # Check log file

    [[ "$error" != true ]] && printf "\e[1m[success] Test completed. No errors found\e[0m\n\n"
    [[ "$log_error" != true ]] && printf "Log:\n%s\n" "$(<$DOMAIN_LOG)"
    [[ "$error" == true ]] && { printf "\n"; exit 1; }  # Exit with error if test failed
}

function test_dead_check {
    # Test addition of resurrected domains
    # Input
    printf "www.google.com\n" > "$DEAD_DOMAINS"  # Subdomains should be stripped
    printf "584031dead-domain-test.com\n" >> "$DEAD_DOMAINS"
    # Expected output
    printf "google.com\n" >> out_raw.txt
    printf "584031dead-domain-test.com\n" >> out_dead.txt
    printf "resurrected,google.com,dead_domains_file\n" >> out_log.txt

    # Test removal of dead domains with subdomains
    : > "$SUBDOMAINS"  # Initialize subdomains file
    printf "584308-dead-subdomain-test.com\n" >> "$RAW"  # Input
    printf "584308-dead-subdomain-test.com\n" > "$ROOT_DOMAINS"  # Input
    while read -r subdomain; do
        subdomain="${subdomain}.584308-dead-subdomain-test.com"
        printf "%s\n" "$subdomain" >> "$SUBDOMAINS"  # Input
        printf "%s\n" "$subdomain" >> out_dead.txt  # Expected output
    done < "$SUBDOMAINS_TO_REMOVE"
    printf "%s\n" "dead,584308-dead-subdomain-test.com,raw" >> out_log.txt  # Expected output

    # Test removal of dead redundant domains and wildcards
    : > "$REDUNDANT_DOMAINS"  # Initialize redundant domains file
    printf "493053dead-wildcard-test.com\n" >> "$RAW"  # Input
    printf "493053dead-wildcard-test.com\n" > "$WILDCARDS"  # Input
    {
        printf "redundant-1.493053dead-wildcard-test.com\n"
        printf "redundant-2.493053dead-wildcard-test.com\n"
    } >> "$REDUNDANT_DOMAINS"  # Input
    {
        printf "redundant-1.493053dead-wildcard-test.com\n"
        printf "redundant-2.493053dead-wildcard-test.com\n"
    } >> out_dead.txt  # Expected output
    {
        printf "dead,493053dead-wildcard-test.com,wildcard\n"
        printf "dead,493053dead-wildcard-test.com,wildcard\n"
    } >> out_log.txt  # Expected output

    # Check removal of dead domains
    # Input
    printf "apple.com\n" >> "$RAW"
    printf "49532dead-domain-test.com\n" >> "$RAW"  # Input
    # Expected output
    printf "apple.com\n" >> out_raw.txt
    printf "49532dead-domain-test.com\n" >> out_dead.txt
    printf "dead,49532dead-domain-test.com,raw\n" >> out_log.txt

    # Test raw light file
    cp "$RAW" "$RAW_LIGHT"
    grep -vF 'google.com' out_raw.txt > out_raw_light.txt  # Expected output for light (resurrected domains are not added back to light)

    run_script "check_dead.sh"
    check_output "$RAW" "out_raw.txt" "Raw"  # Check raw file
    check_output "$RAW_LIGHT" "out_raw_light.txt" "Raw light"  # Check raw light file
    check_output "$DEAD_DOMAINS" "out_dead.txt" "Dead domains"  # Check dead domains file
    check_if_dead_present "$SUBDOMAINS" "Subdomains"  # Check subdomains file
    check_if_dead_present "$ROOT_DOMAINS" "Root domains"  # Check root domains file
    check_if_dead_present "$REDUNDANT_DOMAINS" "Redundant domains"  # Check redundant domains file
    check_if_dead_present "$WILDCARDS" "Wildcards"  # Check wildcards file
    check_log  # Check log file

    [[ "$error" != true ]] && printf "\e[1m[success] Test completed. No errors found\e[0m\n\n" ||
        printf "\e[1m[warn] The dead-domains-linter may have false positives. Rerun the job to confirm\e[0m\n\n"
    [[ "$log_error" != true ]] && printf "Log:\n%s\n" "$(<$DOMAIN_LOG)"
    [[ "$error" == true ]] && { printf "\n"; exit 1; }  # Exit with error if test failed
}

function test_parked_check {
    # Placeholders needed as sample data (split does not work well without enough records)
    not_parked_placeholder=$(head -n 50 "$TOPLIST")
    parked_placeholder=$(head -n 50 "$PARKED_DOMAINS")
    printf "%s\n" "$not_parked_placeholder" > placeholders.txt
    printf "%s\n" "$not_parked_placeholder" > "$RAW"
    printf "%s\n" "$parked_placeholder" >> placeholders.txt
    printf "%s\n" "$parked_placeholder" > "$PARKED_DOMAINS"

    # Test addition of unparked domains in parked domains file
    printf "google.com\n" >> "$PARKED_DOMAINS"  # Unparked domain as input
    # Expected output
    printf "google.com\n" >> out_raw.txt
    printf "unparked,google.com,parked_domains\n" >> out_log.txt

    # Test removal of parked domains
    # Input
    printf "tradexchange.online\n" >> "$RAW"
    printf "apple.com\n" >> "$RAW"
    # Expected output
    printf "tradexchange.online\n" >> out_parked.txt
    printf "apple.com\n" >> out_raw.txt
    printf "parked,tradexchange.online,raw\n" >> out_log.txt

    # Test raw light file
    cp "$RAW" "$RAW_LIGHT"
    grep -vxF 'google.com' out_raw.txt > out_raw_light.txt  # Unparked domains are not added back to light

    run_script "check_parked.sh"

    # Remove placeholder lines
    comm -23 "$RAW" placeholders.txt > raw.tmp
    comm -23 "$RAW_LIGHT" placeholders.txt > raw_light.tmp
    grep -vxFf placeholders.txt "$PARKED_DOMAINS" > parked.tmp
    mv raw.tmp "$RAW"
    mv raw_light.tmp "$RAW_LIGHT"
    mv parked.tmp "$PARKED_DOMAINS"

    check_output "$RAW" "out_raw.txt" "Raw"  # Check raw file
    check_output "$RAW_LIGHT" "out_raw_light.txt" "Raw light"  # Check raw light file
    check_output "$PARKED_DOMAINS" "out_parked.txt" "Parked domains"  # Check parked domains file
    check_log  # Check log file
    [[ "$error" != true ]] && printf "\e[1m[success] Test completed. No errors found\e[0m\n\n"
    [[ "$error" == true ]] && { printf "\n"; exit 1; }  # Exit with error if test failed
}

function run_script {
    for file in out_*; do  # Format expected output files
        [[ "$file" != out_dead.txt ]] && [[ "$file" != out_parked.txt ]] && sort "$file" -o "$file"
    done
    printf "\e[1m[start] %s\e[0m\n" "$1"
    printf "%s\n" "----------------------------------------------------------------------"
    bash "functions/${1}" || errored=true
    printf "%s\n" "----------------------------------------------------------------------"
    [[ -z "$2" ]] && [[ "$errored" == true ]] && { printf "\e[1m[warn] Script returned an error\e[0m\n"; error=true; }  # Check exit status
}

function check_output {
    cmp -s "$1" "$2" && return  # Return if files are the same
    printf "\e[1m[warn] %s file is not as expected:\e[0m\n" "$3"
    cat "$1"
    printf "\n[info] Expected output:\n"
    cat "$2"
    printf "\n"
    error=true
}

function check_if_dead_present {
    ! grep -q '[[:alnum:]]' "$1" && return  # Return if file has no domains
    printf "\e[1m[warn] %s file still has dead domains:\e[0m\n" "$2"
    cat "$1"
    printf "\n"
    error=true
}

check_log() {
    # Check that all required log terms are found in the log file
    while read -r log_term; do
        ! grep -qF "$log_term" "$DOMAIN_LOG" && { log_error=true; break; }
    done < out_log.txt

    [[ "$log_error" != true ]] && return

    printf "\e[1m[warn] Log file is not as expected:\e[0m\n"
    cat "$DOMAIN_LOG"
    printf "\n[info] Terms expected in log:\n"
    cat out_log.txt
    # No need for additional new line since the log is not printed again
    error=true
}

main "$1"

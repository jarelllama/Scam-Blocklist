#!/bin/bash

# This script is used to test the various functions/scripts of this project.
# Each test consist of an input file which will be processed by
# the called script, and an output file which is the expected results
# from the processing. The input and output files are compared to determine
# the success or failure of the test.

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

main() {
    # Initialize
    : > "$RAW"
    sed -i '1q' "$DOMAIN_LOG"
    error=false

    case "$1" in
        ('retrieve')
            TEST_RETRIEVE_VALIDATE "$1" ;;
        ('validate')
            TEST_RETRIEVE_VALIDATE "$1" ;;
        ('dead')
            test_dead_check ;;
        ('parked')
            test_parked_check ;;
        ('shellcheck')
            SHELLCHECK ;;
    esac

    exit 0
}

# Function 'SHELLCHECK' runs ShellCheck for all scripts along with other checks
# for common errors/mistakes.
SHELLCHECK() {
    # Download ShellCheck
    url='https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.linux.x86_64.tar.xz'
    wget -qO - "$url" | tar -xJ

    printf "%s\n" "$(shellcheck-stable/shellcheck --version)"

    # Find scripts
    scripts=$(find . ! -path "./legacy/*" -type f -name "*.sh")

    # Run ShellCheck for each script
    while read -r script; do
        shellcheck-stable/shellcheck "$script" || error=true
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

    # Exit with error if test failed
    if [[ "$error" == true ]]; then
        printf "\n"
        exit 1
    fi
}

# The 'test_<function>' scripts are to test individual functions within scripts
# The input.txt file is to be processed by the called script. The out_raw.txt
# file is the expected raw file after processing by the called script.

# TEST: conversion from URLs to domains
test_conversion() {
    # INPUT
    printf "https://conversion-test.com/folder/" >> input.txt
    # EXPECTED OUTPUT
    printf "conversion-test.com" >> out_raw.txt
}

# TEST: removal of known dead domains
test_known_dead_removal() {
    {
        printf "dead-test.com\n"
        printf "www.dead-test-2.com\n"
    } >> "$DEAD_DOMAINS"  # Known dead domains
    {
        printf "dead-test.com\n"
        printf "www.dead-test-2.com\n"
    } >> input.txt  # INPUTS

    # No expected output (dead domains check does not log)
}

# TEST: removal of common subdomains
test_subdomain_removal() {
    while read -r subdomain; do
        subdomain="${subdomain}.subdomain-test.com"

        # INPUT
        printf "%s\n" "$subdomain" >> input.txt

        # EXPECTED OUTPUTS
        printf "%s\n" "$subdomain" >> out_subdomains.txt
        grep -v 'www.' <(printf "subdomain,%s" "$subdomain") >> out_log.txt
    done < "$SUBDOMAINS_TO_REMOVE"

    # EXPECTED OUTPUTS
    if [[ "$script_to_test" == 'validate' ]]; then
        # Only the retrieval script skips logging 'www.' subdomains
        printf "subdomain,www.subdomain-test.com\n" >> out_log.txt
    fi
    printf "subdomain-test.com\n" >> out_raw.txt
    printf "subdomain-test.com\n" >> out_root_domains.txt
}

# TEST: removal of know parked domains
test_known_parked_removal() {
    # Known parked domain
    printf "parked-domains-test.com\n" >> "$PARKED_DOMAINS"
    # INPUT
    printf "parked-domains-test.com\n" >> input.txt
    # EXPECTED OUTPUT
    printf "parked,parked-domains-test.com\n" >> out_log.txt
}

# TEST: whitelisted domains removal
test_whitelist_removal() {
    # Sample whitelist term
    printf "whitelist\n" >> "$WHITELIST"
    # Sample blacklisted domain
    printf "whitelist-blacklisted-test.com\n" >> "$BLACKLIST"
    # INPUTS
    printf "whitelist-test.com\n" >> input.txt
    printf "whitelist-blacklisted-test.com\n" >> input.txt

    # EXPECTED OUTPUTS
    printf "whitelist-blacklisted-test.com\n" >> out_raw.txt
    printf "whitelist,whitelist-test.com\n" >> out_log.txt
    # The check script does not log blacklisted domains
    [[ "$script_to_test" == 'check' ]] && return
    printf "blacklist,whitelist-blacklisted-test.com\n" >> out_log.txt
}

# TEST: removal of domains with whitelisted TLDs
test_whitelisted_tld_removal() {
    {
        printf "white-tld-test.gov\n"
        printf "white-tld-test.edu\n"
        printf "white-tld-test.mil\n"
    } >> input.txt  # INPUTS
    {
        printf "tld,white-tld-test.gov\n"
        printf "tld,white-tld-test.edu\n"
        printf "tld,white-tld-test.mil\n"
    } >> out_log.txt  # EXPECTED OUTPUTS
}

# TEST: removal of invalid entries and IP addresses
test_invalid_removal() {
    {
        printf "invalid-test-com\n"
        printf "100.100.100.100\n"
        printf "invalid-test.xn--903fds\n"
        printf "invalid-test.x\n"
        printf "invalid-test.100\n"
        printf "invalid-test.1x\n"
    } >> input.txt  # INPUTS

    # EXPECTED OUTPUTS
    printf "invalid-test.xn--903fds\n" >> out_raw.txt
    {
        printf "invalid,invalid-test-com\n"
        printf "invalid,100.100.100.100\n"
        printf "invalid,invalid-test.x\n"
        printf "invalid,invalid-test.100\n"
        printf "invalid,invalid-test.1x\n"
    } >> out_log.txt

    # Check script does not save invalid domains to manual review file
    [[ "$script_to_test" == 'check' ]] && return

    {
        printf "invalid-test-com\n"
        printf "100.100.100.100\n"
        printf "invalid-test.x\n"
        printf "invalid-test.100\n"
        printf "invalid-test.1x\n"
    } >> out_manual.txt
}

test_redundant_removal() {
    if [[ "$script_to_test" == 'retrieve' ]]; then
        # Test removal of redundant domains during retrieval
        printf "redundant-test.com\n" > "$WILDCARDS"
         # Wildcard should already be in expected wildcards file
        printf "redundant-test.com\n" >> out_wildcards.txt
        # INPUT
        printf "domain.redundant-test.com\n" >> input.txt
        # EXPECTED OUTPUT
        printf "redundant,domain.redundant-test.com\n" >> out_log.txt
        return
    fi
    # Test addition of new wildcard from wildcard file
    # (manually adding a new wildcard to wildcards file)
    # Existing redundant domain in raw file
    printf "domain.redundant-test.com\n" >> input.txt
    # INPUT
    printf "redundant-test.com\n" > "$WILDCARDS"
    # EXPECTED OUTPUTS
    printf "redundant-test.com\n" >> out_raw.txt
    printf "redundant-test.com\n" >> out_wildcards.txt
    printf "domain.redundant-test.com\n" >> out_redundant.txt
    printf "redundant,domain.redundant-test.com\n" >> out_log.txt
}

# TEST: removal of domains found in toplist
test_toplist_removal() {
    if [[ "$script_to_test" == 'retrieve' ]]; then
        # INPUT
        printf "microsoft.com\n" >> data/pending/domains_manual.tmp
        # EXPECTED OUTPUTS
        printf "microsoft.com\n" >> out_manual.txt
        printf "toplist,microsoft.com\n" >> out_log.txt
        return
    fi
    # INPUT
    printf "microsoft.com\n" >> input.txt
    # EXPECTED OUTPUTS
    printf "microsoft.com\n" >> out_raw.txt
    printf "toplist,microsoft.com\n" >> out_log.txt
}

# TEST: test exclusion of specific sources from light version
test_light_build() {
    cp "$RAW" "$RAW_LIGHT"
    # INPUT
    printf "raw-light-test.com\n" >> data/pending/domains_guntab.com.tmp
    # EXPECTED OUTPUT
    printf "raw-light-test.com\n" >> out_raw.txt
    # Domain from excluded source should not be in output
    grep -vF "raw-light-test.com" out_raw.txt > out_raw_light.txt
}

# Function 'TEST_RETRIEVE_VALIDATE' can test both the retrieval process and the
# validation process depending on which argument is passed to the function.
# $1: script to test, can either be 'retrieve' or 'validate'
TEST_RETRIEVE_VALIDATE() {
    script_to_test="$1"

    # Initialize files
    : > "$DEAD_DOMAINS"
    : > "$SUBDOMAINS"
    : > "$ROOT_DOMAINS"
    : > "$PARKED_DOMAINS"
    : > "$WHITELIST"
    : > "$BLACKLIST"
    : > "$REDUNDANT_DOMAINS"

    # Initialize pending directory
    [[ -d data/pending ]] && rm -r data/pending
    [[ "$script_to_test" == 'retrieve' ]] && mkdir data/pending

    # Note removal of domains already in raw file is redundant to test

    if [[ "$script_to_test" == 'retrieve' ]]; then
        test_conversion
        test_known_dead_removal
        test_known_parked_removal
        test_light_build
    fi

    test_subdomain_removal
    test_whitelist_removal
    test_whitelisted_tld_removal
    test_invalid_removal
    test_redundant_removal
    test_toplist_removal

    # Prepare and run retrieval script
    if [[ "$script_to_test" == 'retrieve' ]]; then
        # Distribute the sample input into various sources
        split -n l/3 input.txt
        mv xaa data/pending/domains_aa419.org.tmp
        mv xab data/pending/domains_google_search_search-term-1.tmp
        mv xac data/pending/domains_google_search_search-term-2.tmp

        run_script retrieve_domains.sh
    fi

    # Prepare and run check script
    if [[ "$script_to_test" == 'validate' ]]; then
        # Use input.txt as sample raw files to test
        cp input.txt "$RAW"
        cp input.txt "$RAW_LIGHT"

        # Expected output for light version
        cp out_raw.txt out_raw_light.txt

        run_script validate_raw.sh
    fi

    # Check and verify outputs

    check_output "$RAW" out_raw.txt Raw
    check_output "$RAW_LIGHT" out_raw_light.txt "Raw light"
    check_output "$SUBDOMAINS" out_subdomains.txt Subdomains
    check_output "$ROOT_DOMAINS" out_root_domains.txt "Root domains"

    # Check entries saved for manual review
    if [[ "$script_to_test" == 'retrieve' ]]; then
        check_output "data/pending/domains_guntab.com.tmp" "out_manual.txt" "Manual review"
    fi

    if [[ "$script_to_test" == 'validate' ]]; then
        check_output "$REDUNDANT_DOMAINS" "out_redundant.txt" "Redundant domains"
        check_output "$WILDCARDS" "out_wildcards.txt" "Wildcards"
    fi

    check_log

    on_exit
}

# Function 'test_dead_check' tests the removal/addition of dead and resurrected
# domains respectively.
test_dead_check() {
    # Initialize files
    : > "$SUBDOMAINS"
    : > "$ROOT_DOMAINS"

    # Test addition of resurrected domains
    # Input
    printf "www.google.com\n" > "$DEAD_DOMAINS"  # Subdomains should be stripped
    printf "584031dead-domain-test.com\n" >> "$DEAD_DOMAINS"
    # Expected output
    printf "google.com\n" >> out_raw.txt
    printf "584031dead-domain-test.com\n" >> out_dead.txt
    printf "resurrected,google.com,dead_domains_file\n" >> out_log.txt

    # TEST: removal of dead domains with subdomains
    # Dead root domains
    printf "584308-dead-subdomain-test.com\n" >> "$RAW"
    printf "584308-dead-subdomain-test.com\n" >> "$ROOT_DOMAINS"
    while read -r subdomain; do
        subdomain="${subdomain}.584308-dead-subdomain-test.com"
        # INPUT
        printf "%s\n" "$subdomain" >> "$SUBDOMAINS"
        # EXPECTED OUTPUT
        printf "%s\n" "$subdomain" >> out_dead.txt
    done < "$SUBDOMAINS_TO_REMOVE"
    # EXPECTED OUTPUT
    printf "%s\n" "dead,584308-dead-subdomain-test.com,raw" >> out_log.txt

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
    pick_exit
}

# Function 'run_script' executes the script passed by the caller.
# Input:
#   $1: scrip to execute
# Output:
#   return 1 if script has an exit status of 1
run_script() {
    # Format expected output files
    for file in out_*; do
        if [[ "$file" != out_dead.txt && "$file" != out_parked.txt ]]; then
            sort "$file" -o "$file"
        fi
    done

    printf "\e[1m[start] %s\e[0m\n" "$1"
    printf "%s\n" "----------------------------------------------------------------------"

    # Run script
    bash "functions/${1}" || errored=true

    printf "%s\n" "----------------------------------------------------------------------"

    # Return 1 if script has an exit status of 1
    if [[ "$errored" == true ]]; then
        return 1
    fi
}

# Function 'on_exit' checks if the script should exit with an
# exit status of 1 or 0.
on_exit() {
    # Test completed successfully
    [[ "$error" != true ]] && printf "\e[1m[success] Test completed. No errors found\e[0m\n\n"

    # Print log if not already printed by 'check_log' function
    [[ "$log_error" != true ]] && printf "Log:\n%s\n" "$(<$DOMAIN_LOG)"

    # Exit with error if test failed
    [[ "$error" == true ]] && { printf "\n"; exit 1; }
}

check_temp() {
    if ! ls x?? &> /dev/null && ! ls ./*.tmp &> /dev/null; then
        return
    fi
    printf "\e[1m[warn] Temporary files were not removed:\e[0m\n"
    ls x?? ./*.tmp 2> /dev/null
    error=true
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

[[ "$CI" == true ]] && main "$1"  # Do not allow running locally
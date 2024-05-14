#!/bin/bash

# This script is used to test the various functions/scripts of this project.
# Each test consists of an input file which will be processed by the called
# script, and an output file which is the expected results from the processing.
# The input and output files are compared to determine the success or failure
# of the test.

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly WHITELIST='config/whitelist.txt'
readonly BLACKLIST='config/blacklist.txt'
readonly WILDCARDS='config/wildcards.txt'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'
readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly ADBLOCK='lists/adblock'
readonly DOMAINS='lists/wildcard_domains'
readonly DOMAIN_LOG='config/domain_log.csv'
readonly SOURCE_LOG='config/source_log.csv'

main() {
    # Initialize
    for file in "$RAW" "$DEAD_DOMAINS" "$SUBDOMAINS" "$ROOT_DOMAINS" \
        "$PARKED_DOMAINS" "$WHITELIST" "$BLACKLIST" "$WILDCARDS"; do
        : > "$file"
    done
    sed -i '1q' "$DOMAIN_LOG"
    sed -i '1q' "$SOURCE_LOG"
    error=false

    case "$1" in
        'retrieve')
            TEST_RETRIEVE_VALIDATE "$1" ;;
        'validate')
            TEST_RETRIEVE_VALIDATE "$1" ;;
        'dead')
            TEST_DEAD_CHECK ;;
        'parked')
            TEST_PARKED_CHECK ;;
        'build')
            TEST_BUILD ;;
        'shellcheck')
            SHELLCHECK ;;
        *)
            exit 1 ;;
    esac
}

# Function 'SHELLCHECK' runs ShellCheck for all scripts along with other checks
# for common errors/mistakes.
SHELLCHECK() {
    printf "\e[1m[start] ShellCheck\e[0m\n"

    # Install ShellCheck
    url='https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.linux.x86_64.tar.xz'
    curl -sSL "$url" | tar -xJ

    # Check that ShellCheck was successfully installed
    shellcheck-stable/shellcheck --version || exit 1

    # Find scripts
    scripts=$(find . -type f -name "*.sh")

    # Run ShellCheck for each script
    while read -r script; do
        shellcheck-stable/shellcheck "$script" || error=true
    done <<< "$scripts"

    # Check for carriage return characters
    files=$(grep -rl $'\r' --exclude-dir={.git,shellcheck-stable} .)
    if [[ -n "$files" ]]; then
        printf "\n\e[1m[warn] Lines with carriage return characters:\e[0m\n"
        printf "%s\n" "$files"
        error=true
    fi

    # Check for missing space before comments
    files=$(grep -rn '\S\s#\s' --exclude-dir={.git,shellcheck-stable} \
        --exclude=*.csv .)
    if [[ -n "$files" ]]; then
        printf "\n\e[1m[warn] Lines with missing space before comments:\e[0m\n"
        printf "%s\n" "$files"
        error=true
    fi

    printf "\n[info] Scripts checked (%s):\n%s\n\n" \
        "$(wc -w <<< "$scripts")" "$scripts"

    [[ "$error" == true ]] && exit 1

    printf "\e[1m[success] Test completed. No errors found\e[0m\n"
}

# Function 'TEST_RETRIEVE_VALIDATE' can test both the retrieval process and the
# validation process depending on which argument is passed to the function.
#   $1: script to test ('retrieve' or 'validate')
TEST_RETRIEVE_VALIDATE() {
    script_to_test="$1"

    # Initialize pending directory
    rm -r data/pending 2> /dev/null
    mkdir -p data/pending

    # Note removal of domains already in raw file is redundant to test

    test_punycode_conversion
    test_subdomain_removal
    test_whitelist_blacklist
    test_whitelisted_tld_removal
    test_invalid_removal
    test_toplist_removal

    if [[ "$script_to_test" == 'retrieve' ]]; then
        test_manual_addition
        test_url_conversion
        test_known_dead_removal
        test_known_parked_removal
        test_light_build

        # Distribute the sample input into various sources
        split -n l/3 input.txt
        mv xaa data/pending/domains_aa419.org.tmp
        mv xab data/pending/domains_google_search_search-term-1.tmp
        mv xac data/pending/domains_google_search_search-term-2.tmp

        # Prepare sample raw light file
        cp "$RAW" "$RAW_LIGHT"

        # Run retrieval script
        run_script retrieve_domains.sh
    fi

    if [[ "$script_to_test" == 'validate' ]]; then
        # Use input.txt as sample raw files to test
        cp input.txt "$RAW"
        cp "$RAW" "$RAW_LIGHT"

        # Expected output for light version
        cp out_raw.txt out_raw_light.txt

        # Run validation script
        run_script validate_domains.sh
    fi

    ### Check and verify outputs

    check_output "$RAW" out_raw.txt Raw
    check_output "$RAW_LIGHT" out_raw_light.txt "Raw light"
    check_output "$SUBDOMAINS" out_subdomains.txt Subdomains
    check_output "$ROOT_DOMAINS" out_root_domains.txt "Root domains"

    if [[ "$script_to_test" == 'retrieve' ]]; then
        # Check entries saved for manual review
        check_output data/pending/domains_scamadviser.com.tmp \
            out_manual_review.txt "Manual review"

        # Check source log
        check_terms "$SOURCE_LOG" out_source_log.txt "Source log"
    else
        check_output "$DEAD_DOMAINS" out_dead.txt "Dead domains"
    fi

    check_and_exit
}

# Function 'TEST_DEAD_CHECK' tests the removal/addition of dead and resurrected
# domains respectively.
TEST_DEAD_CHECK() {
    test_dead_check
    test_alive_check

    # Prepare sample raw light file
    cp "$RAW" "$RAW_LIGHT"
    # Expected output for light version
    # (resurrected domains are not added back into light)
    grep -vxF 'www.google.com' out_raw.txt > out_raw_light.txt

    # Run script
    run_script check_dead.sh

    # Sort dead domains file for easier comparison with expected output
    sort "$DEAD_DOMAINS" -o "$DEAD_DOMAINS"

    ### Check and verify outputs
    check_output "$RAW" out_raw.txt Raw
    check_output "$RAW_LIGHT" out_raw_light.txt "Raw light"
    check_output "$DEAD_DOMAINS" out_dead.txt "Dead domains"
    check_output "$SUBDOMAINS" out_subdomains.txt Subdomains
    check_output "$ROOT_DOMAINS" out_root_domains.txt "Root domains"

    check_and_exit
}

# Function 'TEST_PARKED_CHECK' tests the removal/addition of parked and
# unparked domains respectively.
TEST_PARKED_CHECK() {
    # Generate placeholders
    # (split does not work well without enough records)
    for i in {1..30};do
        printf "placeholder%s.com\n" "$i" >> placeholders.txt
    done
    cat placeholders.txt >> "$RAW"
    cat placeholders.txt >> "$PARKED_DOMAINS"

    test_parked_check
    test_unparked_check

    # Prepare sample raw light file
    cp "$RAW" "$RAW_LIGHT"
    # Expected output for light version
    # (Unparked domains are not added back into light)
    grep -vxF 'www.google.com' out_raw.txt > out_raw_light.txt

    # Run script
    run_script check_parked.sh

    # Remove placeholder line
    for file in "$RAW" "$RAW_LIGHT" "$PARKED_DOMAINS"; do
        grep -vxFf placeholders.txt "$file" > temp
        mv temp "$file"
    done
    # Not exact match in domain log
    grep -vFf placeholders.txt "$DOMAIN_LOG" > temp
    mv temp "$DOMAIN_LOG"

    # Sort parked domains file for easier comparison with expected output
    sort "$PARKED_DOMAINS" -o "$PARKED_DOMAINS"

    ### Check and verify outputs
    check_output "$RAW" out_raw.txt Raw
    check_output "$RAW_LIGHT" out_raw_light.txt "Raw light"
    check_output "$PARKED_DOMAINS" out_parked.txt "Parked domains"
    check_output "$SUBDOMAINS" out_subdomains.txt Subdomains
    check_output "$ROOT_DOMAINS" out_root_domains.txt "Root domains"

    check_and_exit
}

# Function 'TEST_BUILD' verifies that the various formats of blocklist are
# correctly built with the right syntax.
TEST_BUILD() {
    # INPUT
    printf "build-test.com\n" >> "$WILDCARDS"
    printf "redundant.build-test.com\n" >> "$RAW"

    # EXPECTED OUTPUT
    printf "[Adblock Plus]\n" >> out_adblock.txt
    printf "||build-test.com^\n" >> out_adblock.txt
    printf "build-test.com\n" >> out_domains.txt
    cp out_adblock.txt out_adblock_light.txt
    cp out_domains.txt out_domains_light.txt

    # Prepare sample raw light file
    cp "$RAW" "$RAW_LIGHT"

    # Run script
    run_script build_lists.sh

    # Remove comments from the blocklists (keeps Adblock Plus header)
    for file in lists/*/*.txt; do
        sed -i '/[#!]/d' "$file"
    done

    ### Check and verify outputs
    check_output "${ADBLOCK}/scams.txt" out_adblock.txt Adblock
    check_output "${DOMAINS}/scams.txt" out_domains.txt "Wildcard Domains"
    check_output "${ADBLOCK}/scams_light.txt" out_adblock_light.txt "Adblock light"
    check_output "${DOMAINS}/scams_light.txt" out_domains_light.txt "Wildcard Domains light"

    [[ "$error" == true ]] && exit 1

    printf "\e[1m[success] Test completed. No errors found\e[0m\n"
}

# The 'test_<process>' functions are to test individual processes within
# scripts. The input.txt file is to be processed by the called script. The
# out_<name>.txt file is the expected output after processing by the called
# script.

### RETRIEVAL/VALIDATION TESTS

# TEST: manual addition of domains from repo issue
test_manual_addition() {
    # INPUT
    # Note URL conversion is done in the workflow now
    # Also test removal of square brackets
    printf "manual-addition-test[.]com\n" >> data/pending/domains_manual.tmp
    # EXPECTED OUTPUT
    printf "manual-addition-test.com\n" >> out_raw.txt

    # Test proper logging in the logs. This test is only done once here since
    # it applies to all newly added domains to the raw file.
    printf "saved,manual-addition-test.com,Manual\n" >> out_log.txt
    printf ",Manual,,1,1,0,0,0,0,,saved\n" >> out_source_log.txt
}

# TEST: conversion to Punycode
test_punycode_conversion() {
    # INPUT
    printf "punycodé-test.cöm\n" >> input.txt
    # EXPECTED OUTPUT
    printf "xn--punycod-test-heb.xn--cm-fka\n" >> out_raw.txt
}

# TEST: conversion of URLs to domains
test_url_conversion() {
    # INPUT
    printf "https://conversion-test.com/\n" >> input.txt
    printf "http://conversion-test-2.com/\n" >> input.txt
    # EXPECTED OUTPUT
    printf "conversion-test.com\n" >> out_raw.txt
    printf "conversion-test-2.com\n" >> out_raw.txt
}

# TEST: removal of known dead domains
test_known_dead_removal() {
    {
        printf "www.dead-test.com\n"
    } >> "$DEAD_DOMAINS"  # Known dead domains
    # Dead subdomains should be matched
    {
        printf "www.dead-test.com\n"
    } >> input.txt  # INPUT

    # Expected output: domain not in raw file/raw light file
}

# TEST: removal of known parked domains
test_known_parked_removal() {
    {
        printf "www.parked-test.com\n"
    } >> "$PARKED_DOMAINS"  # Known parked domains
    # Parked subdomains should be matched
    {
        printf "www.parked-test.com\n"
    } >> input.txt  # INPUT

   # Expected output: domains not in raw file/raw light file
}

# TEST: removal of common subdomains
test_subdomain_removal() {
    while read -r subdomain; do
        subdomain="${subdomain}.subdomain-test.com"
        # INPUT
        printf "%s\n" "$subdomain" >> input.txt
        # EXPECTED OUTPUT
        printf "%s\n" "$subdomain" >> out_subdomains.txt
        printf "subdomain,%s" "$subdomain" | mawk '!/www\./' >> out_log.txt
    done < "$SUBDOMAINS_TO_REMOVE"

    # EXPECTED OUTPUT
    printf "subdomain-test.com\n" >> out_raw.txt
    printf "subdomain-test.com\n" >> out_root_domains.txt
    # The retrieval script does not log 'www.' subdomains
    [[ "$script_to_test" == 'retrieve' ]] && return
    printf "subdomain,www.subdomain-test.com\n" >> out_log.txt
}

# TEST: whitelisted domains removal and blacklist logging
test_whitelist_blacklist() {
    # Sample whitelist term
    printf '^whitelist-test\.com$\n' >> "$WHITELIST"
    # Sample blacklisted domain
    printf "whitelist-blacklisted-test.com\n" >> "$BLACKLIST"
    # INPUT
    printf "whitelist-test.com\n" >> input.txt
    printf "whitelist-blacklisted-test.com\n" >> input.txt

    # EXPECTED OUTPUT
    printf "whitelist-blacklisted-test.com\n" >> out_raw.txt
    printf "whitelist,whitelist-test.com\n" >> out_log.txt
    # The validate script does not log blacklisted domains
    [[ "$script_to_test" == 'validate' ]] && return
    printf "blacklist,whitelist-blacklisted-test.com\n" >> out_log.txt
}

# TEST: removal of domains with whitelisted TLDs
test_whitelisted_tld_removal() {
    {
        printf "white-tld-test.gov.us\n"
        printf "white-tld-test.edu\n"
        printf "white-tld-test.mil\n"
    } >> input.txt  # INPUT
    {
        printf "tld,white-tld-test.gov.us\n"
        printf "tld,white-tld-test.edu\n"
        printf "tld,white-tld-test.mil\n"
    } >> out_log.txt  # EXPECTED OUTPUT
}

# TEST: removal of non-domain entries
test_invalid_removal() {
    if [[ "$script_to_test" == 'retrieve' ]]; then
        # INPUT
        {
            # Invalid subdomains/root domains should not make it into
            # subdomains/root domains file
            printf "www.invalid-test-com\n"
            printf "100.100.100.1\n"
            printf "invalid-test.xn--903fds\n"
            printf "invalid-test.x\n"
            printf "invalid-test.100\n"
            printf "invalid-test.1x\n"
        } >> data/pending/domains_scamadviser.com.tmp

        # EXPECTED OUTPUT
        # The retrieval script saves invalid entries to the manual review file
        {
            printf "invalid-test-com\n"
            printf "100.100.100.1\n"
            printf "invalid-test.x\n"
            printf "invalid-test.100\n"
            printf "invalid-test.1x\n"
        } >> out_manual_review.txt

        printf "invalid-test.xn--903fds\n" >> out_raw.txt
        {
            printf "invalid,invalid-test-com,scamadviser.com\n"
            printf "invalid,100.100.100.1,scamadviser.com\n"
            printf "invalid,invalid-test.x,scamadviser.com\n"
            printf "invalid,invalid-test.100,scamadviser.com\n"
            printf "invalid,invalid-test.1x,scamadviser.com\n"
        } >> out_log.txt

        return
    fi

    # INPUT
    {
        # Invalid subdomains/root domains should not make it into
        # subdomains/root domains file
        printf "www.invalid-test-com\n"
        printf "100.100.100.1\n"
        printf "invalid-test.xn--903fds\n"
        printf "invalid-test.x\n"
    } >> input.txt
    # Validation script checks for invalid entries in the dead domains file
    {
        printf "invalid-test.100\n"
        printf "invalid-test.1x\n"
        printf "dead-domain.com\n"
    } >> "$DEAD_DOMAINS"

    # EXPECTED OUTPUT
    printf "invalid-test.xn--903fds\n" >> out_raw.txt
    printf "dead-domain.com\n" >> out_dead.txt
    {
        printf "invalid,invalid-test-com,raw\n"
        printf "invalid,100.100.100.1,raw\n"
        printf "invalid,invalid-test.x,raw\n"
        printf "invalid,invalid-test.100,dead_domains_file\n"
        printf "invalid,invalid-test.1x,dead_domains_file\n"
    } >> out_log.txt
}

# TEST: removal of domains found in toplist
test_toplist_removal() {
    if [[ "$script_to_test" == 'retrieve' ]]; then
        # INPUT
        printf "microsoft.com\n" >> data/pending/domains_scamadviser.com.tmp
        # EXPECTED OUTPUT
        printf "microsoft.com\n" >> out_manual_review.txt
        printf "toplist,microsoft.com,scamadviser.com\n" >> out_log.txt
        return
    fi

    # INPUT
    printf "microsoft.com\n" >> input.txt
    # EXPECTED OUTPUT
    # The validate script does not save invalid domains to manual review file
    printf "microsoft.com\n" >> out_raw.txt
    printf "toplist,microsoft.com\n" >> out_log.txt
}

# TEST: exclusion of specific sources from light version
test_light_build() {
    # INPUT
    printf "raw-light-test.com\n" >> data/pending/domains_guntab.com.tmp
    # EXPECTED OUTPUT
    printf "raw-light-test.com\n" >> out_raw.txt
    # Domain from excluded source should not be in output
    grep -vxF "raw-light-test.com" out_raw.txt > out_raw_light.txt
}

### DEAD CHECK TESTS

# TEST: removal of dead domains
test_dead_check() {
    # INPUT
    printf "apple.com\n" >> "$RAW"
    printf "49532dead-domain-test.com\n" >> "$RAW"
    printf "49532dead-domain-test.com\n" >> "$ROOT_DOMAINS"
    printf "www.49532dead-domain-test.com\n" >> "$SUBDOMAINS"
    # EXPECTED OUTPUT
    printf "apple.com\n" >> out_raw.txt
    # Subdomains should be kept to be processed by the validation check
    printf "www.49532dead-domain-test.com\n" >> out_dead.txt
    printf "dead,49532dead-domain-test.com,raw\n" >> out_log.txt
    # Both files should be empty (all dead)
    : > out_subdomains.txt
    : > out_root_domains.txt
}

# TEST: addition of resurrected domains
test_alive_check() {
    # INPUT
    printf "www.google.com\n" >> "$DEAD_DOMAINS"
    # EXPECTED OUTPUT
    # Subdomains should be kept to be processed by the validation check
    printf "www.google.com\n" >> out_raw.txt
    printf "resurrected,www.google.com,dead_domains_file\n" >> out_log.txt
}

### PARKED CHECK TESTS

# TEST: removal of parked domains
test_parked_check() {
    # INPUT
    printf "apple.com\n" >> "$RAW"
    printf "tradexchange.online\n" >> "$RAW"
    printf "tradexchange.online\n" >> "$ROOT_DOMAINS"
    printf "www.tradexchange.online\n" >> "$SUBDOMAINS"
    # EXPECTED OUTPUT
    printf "apple.com\n" >> out_raw.txt
    # Subdomains should be kept to be processed by the validation check
    printf "www.tradexchange.online\n" >> out_parked.txt
    printf "parked,tradexchange.online,raw\n" >> out_log.txt
    # Both files should be empty (all dead)
    : > out_subdomains.txt
    : > out_root_domains.txt
}

# TEST: addition of unparked domains
test_unparked_check() {
    # INPUT
    printf "www.google.com\n" >> "$PARKED_DOMAINS"
    printf "parked-errored-test.com\n" >> "$PARKED_DOMAINS"
    # EXPECTED OUTPUT
    # Subdomains should be kept to be processed by the validation check
    printf "www.google.com\n" >> out_raw.txt
    # Domains that errored during curl should be assumed still parked
    printf "parked-errored-test.com\n" >> out_parked.txt
    printf "unparked,www.google.com,parked_domains_file\n" >> out_log.txt
}

### END OF 'test_<process>' functions

# Function 'run_script' executes the script passed by the caller and checks the
# exit status of the script.
# Input:
#   $1: script to execute
run_script() {
    # Format expected output files (ignore not found error)
    for file in out_*; do
        sort "$file" -o "$file" 2> /dev/null
    done

    printf "\e[1m[start] %s\e[0m\n" "$1"
    echo "----------------------------------------------------------------------"

    # Run script
    bash "scripts/${1}" || errored=true

    echo "----------------------------------------------------------------------"

    # Check exit status
    [[ "$errored" != true ]] && return

    printf "\e[1m[warn] Script returned with an error\e[0m\n\n"
    error=true
}

# Function 'check_and_exit' checks if the script should exit with an exit
# status of 1 or 0.
check_and_exit() {
    # Check that all temporary files have been deleted after the run
    if ls x?? &> /dev/null || ls ./*.tmp &> /dev/null; then
        printf "\e[1m[warn] Temporary files were not removed:\e[0m\n"
        ls x?? ./*.tmp 2> /dev/null
        printf "\n"
        error=true
    fi

    # Check domain log
    check_terms "$DOMAIN_LOG" out_log.txt "Domain log" || log_error=true

    # Check if tests were all completed successfully
    if [[ "$error" == false ]]; then
        printf "\e[1m[success] Test completed. No errors found\e[0m\n\n"
    fi

    # Print domain log if not already printed by domain log check
    if [[ "$log_error" != true ]]; then
        printf "Domain log:\n%s\n\n" "$(<"$DOMAIN_LOG")"
    fi

    # Print source log for retrieval test
    if [[ "$script_to_test" == 'retrieve' ]]; then
        printf "Source log:\n%s\n\n" "$(<"$SOURCE_LOG")"
    fi

    [[ "$error" == true ]] && exit 1 || exit 0
}

# Function 'check_terms' checks that a file contains all the given terms.
# Input:
#   $1: file to check
#   $2: file with terms to check for
#   $3: name of file to check
# Output:
#   return 1 (if one or more terms not found)
check_terms() {
    while read -r term; do
        if ! grep -qF "$term" "$1"; then
            local term_error=true
            break
        fi
    done < "$2"

    # Return if all terms found
    [[ "$term_error" != true ]] && return

    printf "\e[1m[warn] %s is not as expected:\e[0m\n" "$3"
    cat "$1"
    printf "\n[info] Terms expected:\n"
    cat "$2"
    printf "\n"
    error=true

    return 1
}

# Function 'check_output' compares the input file with the expected output file
# and prints a warning if they are not the same.
#   $1: input file
#   $2: expected output file
#   $3: name of the file being checked
check_output() {
    cmp -s "$1" "$2" && return  # Return if files are the same
    printf "\e[1m[warn] %s file is not as expected:\e[0m\n" "$3"
    cat "$1"
    printf "\n[info] Expected output:\n"
    cat "$2"
    printf "\n"
    error=true
}

# Entry point

# Do not allow running locally
[[ "$CI" == true ]] && main "$1"

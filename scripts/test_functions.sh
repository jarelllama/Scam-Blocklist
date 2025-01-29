#!/bin/bash

# This script is used to test the various functions/scripts in this repository.
# Each test consists of an input file which will be processed by the called
# script, and an output file which is the expected results from the processing.
# The input and output files are compared to determine the success or failure
# of the test.

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly WHITELIST='config/whitelist.txt'
readonly BLACKLIST='config/blacklist.txt'
readonly WILDCARDS='config/wildcards.txt'
readonly REVIEW_CONFIG='config/review_config.csv'
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
    local file
    for file in "$RAW" "$DEAD_DOMAINS" "$SUBDOMAINS" "$ROOT_DOMAINS" \
        "$PARKED_DOMAINS" "$WHITELIST" "$BLACKLIST" "$WILDCARDS" \
        "$REVIEW_CONFIG"; do
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
    local url scripts files

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
    if files="$(grep -rl $'\r' --exclude-dir={.git,shellcheck-stable} .)"; then
        printf "\n\e[1m[warn] Lines with carriage return characters:\e[0m\n" >&2
        printf "%s\n" "$files" >&2
        error=true
    fi

    # Check for missing space before comments
    if files="$(grep -rn '\S\s#\s' --exclude-dir={.git,shellcheck-stable} \
        --exclude=*.csv .)"; then
        printf "\n\e[1m[warn] Lines with missing space before comments:\e[0m\n" >&2
        printf "%s\n" "$files" >&2
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
    local script_to_test="$1"

    # Initialize pending directory before creating test input files
    [[ -d data/pending ]] && rm -r data/pending
    mkdir -p data/pending

    # Note removal of domains already in raw file is redundant to test
    test_punycode_conversion
    test_subdomain_removal
    test_review_file
    test_whitelist_blacklist
    test_whitelisted_tld_removal
    test_invalid_removal
    test_toplist_check

    if [[ "$script_to_test" == 'retrieve' ]]; then
        test_manual_addition
        test_url_conversion
        test_known_dead_removal
        test_known_parked_removal
        test_light_build

        # Distribute the sample input into various sources
        split -n l/3 input.txt
        mv xaa data/pending/Artists_Against_419.tmp
        mv xab data/pending/google_search_search-term-1.tmp
        mv xac data/pending/google_search_search-term-2.tmp

        # Prepare sample raw light file
        cp "$RAW" "$RAW_LIGHT"

        # Run retrieval script
        run_script retrieve_domains.sh
    fi

    if [[ "$script_to_test" == 'validate' ]]; then
        # Use input.txt as sample raw files to test
        cp input.txt "$RAW"
        cp input.txt "$RAW_LIGHT"

        # Expected output for light version
        cp out_raw.txt out_raw_light.txt

        # Run validation script
        run_script validate_domains.sh
    fi

    ### Check and verify outputs

    check_output "$RAW" out_raw.txt Raw
    check_output "$RAW_LIGHT" out_raw_light.txt 'Raw light'
    check_output "$SUBDOMAINS" out_subdomains.txt Subdomains
    check_output "$ROOT_DOMAINS" out_root_domains.txt 'Root domains'
    check_output "$REVIEW_CONFIG" out_review_config.txt Review
    check_output "$BLACKLIST" out_blacklist.txt Blacklist
    check_output "$WHITELIST" out_whitelist.txt Whitelist

    if [[ "$script_to_test" == 'retrieve' ]]; then
        # Check entries saved for manual review
        check_output data/pending/ScamAdviser.tmp \
            out_manual_review.txt 'Manual review'

        # Check source log
        check_terms "$SOURCE_LOG" out_source_log.txt 'Source log'
    fi

    check_and_exit
}

# Function 'TEST_DEAD_CHECK' tests the removal/addition of dead and resurrected
# domains respectively.
TEST_DEAD_CHECK() {
    # Generate placeholders
    # (split does not work well without enough lines)
    for i in {1..100};do
        printf "placeholder483%s.com\n" "$i" >> "$RAW"
    done

    for i in {101..200};do
        printf "placeholder483%s.com\n" "$i" >> "$DEAD_DOMAINS"
    done

    test_alive_check
    test_dead_check

    # Prepare sample raw light file
    cp "$RAW" "$RAW_LIGHT"
    # Expected output for light version
    # (resurrected domains are not added back into light)
    grep -vxF 'www.google.com' out_raw.txt > out_raw_light.txt

    # Run script
    run_script check_dead.sh checkalive
    run_script check_dead.sh part1
    run_script check_dead.sh part2
    run_script check_dead.sh remove

    # Remove placeholder lines
    for file in "$RAW" "$RAW_LIGHT" "$DEAD_DOMAINS" "$DOMAIN_LOG"; do
        grep -v placeholder "$file" > temp || true
        mv temp "$file"
    done

    ### Check and verify outputs
    check_output "$RAW" out_raw.txt Raw
    check_output "$RAW_LIGHT" out_raw_light.txt 'Raw light'
    check_output "$DEAD_DOMAINS" out_dead.txt 'Dead domains'
    check_output "$SUBDOMAINS" out_subdomains.txt Subdomains
    check_output "$ROOT_DOMAINS" out_root_domains.txt 'Root domains'

    check_and_exit
}

# Function 'TEST_PARKED_CHECK' tests the removal/addition of parked and
# unparked domains respectively.
TEST_PARKED_CHECK() {
    # Generate placeholders
    # (split does not work well without enough lines)
    for i in {1..100};do
        printf "placeholder483%s.com\n" "$i" >> "$RAW"
    done

    for i in {101..200};do
        printf "placeholder483%s.com\n" "$i" >> "$PARKED_DOMAINS"
    done

    test_unparked_check
    test_parked_check

    # Prepare sample raw light file
    cp "$RAW" "$RAW_LIGHT"
    # Expected output for light version
    # (unparked domains are not added back into light)
    grep -vxF 'www.github.com' out_raw.txt > out_raw_light.txt

    # Run script
    run_script check_parked.sh checkunparked
    run_script check_parked.sh part1
    run_script check_parked.sh part2
    run_script check_parked.sh remove

    # Remove placeholder lines
    for file in "$RAW" "$RAW_LIGHT" "$PARKED_DOMAINS" "$DOMAIN_LOG"; do
        grep -v placeholder "$file" > temp || true
        mv temp "$file"
    done

    ### Check and verify outputs
    check_output "$RAW" out_raw.txt Raw
    check_output "$RAW_LIGHT" out_raw_light.txt 'Raw light'
    check_output "$PARKED_DOMAINS" out_parked.txt 'Parked domains'
    check_output "$SUBDOMAINS" out_subdomains.txt Subdomains
    check_output "$ROOT_DOMAINS" out_root_domains.txt 'Root domains'

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
    check_output "${DOMAINS}/scams.txt" out_domains.txt 'Wildcard Domains'
    check_output "${ADBLOCK}/scams_light.txt" out_adblock_light.txt 'Adblock light'
    check_output "${DOMAINS}/scams_light.txt" out_domains_light.txt 'Wildcard Domains light'

    [[ "$error" == true ]] && exit 1

    printf "\e[1m[success] Test completed. No errors found\e[0m\n"
}

# The 'test_<process>' functions are to test individual processes within
# scripts. The input.txt file is to be processed by the called script. The
# out_<name>.txt file is the expected output after processing by the called
# script.

### RETRIEVAL/VALIDATION TESTS

# TEST: manual addition of domains from repo issue, proper logging in domain
# log and source log and removal of square brackets
test_manual_addition() {
    # INPUT
    # Note URL conversion is done in the workflow now
    printf "manual-addition-test[.]com\n" >> data/pending/Manual.tmp
    # EXPECTED OUTPUT
    printf "manual-addition-test.com\n" >> out_raw.txt

    # Test proper logging in the logs. This test is only done once here since
    # it applies to all newly added domains to the raw file.
    printf "saved,manual-addition-test.com,Manual\n" >> out_log.txt
    printf ",Manual,,1,1,0,0,0,0,,saved\n" >> out_source_log.txt
}

# TEST: conversion of Unicode to Punycode
test_punycode_conversion() {
    # INPUT
    printf "punycodé-test.cöm\n" >> input.txt
    # EXPECTED OUTPUT
    printf "xn--punycod-test-heb.xn--cm-fka\n" >> out_raw.txt
}

# TEST: conversion of URLs to domains
test_url_conversion() {
    # INPUT
    printf "https://conversion-test.com\n" >> input.txt
    printf "http://conversion-test-2.com\n" >> input.txt
    # EXPECTED OUTPUT
    printf "conversion-test.com\n" >> out_raw.txt
    printf "conversion-test-2.com\n" >> out_raw.txt
}

# TEST: removal of known dead domains including subdomains
test_known_dead_removal() {
    {
        printf "www.dead-test.com\n"
    } >> "$DEAD_DOMAINS"

    # INPUT
    {
        printf "www.dead-test.com\n"
    } >> input.txt
    # EXPECTED OUTPUT: domain not in raw file/raw light file
}

# TEST: removal of known parked domains including subdomains
test_known_parked_removal() {
    {
        printf "www.parked-test.com\n"
    } >> "$PARKED_DOMAINS"

    # INPUT
    {
        printf "www.parked-test.com\n"
    } >> input.txt
   # EXPECTED OUTPUT: domain not in raw file/raw light file
}

# TEST: removal of common subdomains
test_subdomain_removal() {
    while read -r subdomain; do
        subdomain="${subdomain}.subdomain-test.com"
        # INPUT
        printf "%s\n" "$subdomain" >> input.txt
        # EXPECTED OUTPUT
        printf "%s\n" "$subdomain" >> out_subdomains.txt
        # subdomains are no longer logged
        # 'www' subdomains are not logged
        #printf "subdomain,%s" "$subdomain" | mawk '!/www\./' >> out_log.txt
    done < "$SUBDOMAINS_TO_REMOVE"

    # EXPECTED OUTPUT
    printf "subdomain-test.com\n" >> out_raw.txt
    printf "subdomain-test.com\n" >> out_root_domains.txt
}

# TEST: adding entries to the whitelist and blacklist via the review config
# file
test_review_file() {
    # INPUT
    {
        printf "Source,review-file-test.com,toplist,,\n"
        printf "Source,review-file-misconfigured-test.com,toplist,y,y\n"
        printf "Source,review-file-blacklist-test.com,toplist,y,\n"
        printf "Source,review-file-whitelist-test.com,toplist,,y\n"
    } >> "$REVIEW_CONFIG"
    # EXPECTED OUTPUT
    # Only unconfigured/misconfigured entries should remain in the review config file
    printf "Source,review-file-test.com,toplist,,\n" >> out_review_config.txt
    printf "Source,review-file-misconfigured-test.com,toplist,y,y\n" >> out_review_config.txt

    printf "review-file-blacklist-test.com\n" >> out_blacklist.txt
    printf "^review-file-whitelist-test\.com$\n" >> out_whitelist.txt
}

# TEST: whitelisting and blacklisting entries
test_whitelist_blacklist() {
    # INPUT
    printf "blacklist-test.com\n" >> "$BLACKLIST"
    printf "whitelist-test.com\n" >> "$WHITELIST"
    # Test that the blacklist takes priority over the whitelist
    printf "blacklisted.whitelist-test.com\n" >> "$BLACKLIST"
    {
        printf "blacklist-test.com\n"
        # Test that the whitelist uses regex matching
        printf "regex-test.whitelist-test.com\n"
        printf "blacklisted.whitelist-test.com\n"
    } >> input.txt

    # EXPECTED OUTPUT
    printf "blacklist-test.com\n" >> out_raw.txt
    printf "blacklisted.whitelist-test.com\n" >> out_raw.txt
    printf "whitelist,regex-test.whitelist-test.com\n" >> out_log.txt

    # The validate script does not log blacklisted domains
    [[ "$script_to_test" == 'validate' ]] && return
    printf "blacklist,blacklist-test.com\n" >> out_log.txt
    printf "blacklist,blacklisted.whitelist-test.com\n" >> out_log.txt
}

# TEST: removal of domains with whitelisted TLDs
test_whitelisted_tld_removal() {
    # INPUT
    {
        printf "whitelisted-tld-test.gov.us\n"
        printf "whitelisted-tld-test.edu\n"
        printf "whitelisted-tld-test.mil\n"
        # Test that the blacklist takes priority over the whitelisted TLDs
        printf "blacklisted.whitelisted-tld-test.mil\n"
    } >> data/pending/ScamAdviser.tmp
    printf "blacklisted.whitelisted-tld-test.mil\n" >> "$BLACKLIST"

    # EXPECTED OUTPUT
    printf "blacklisted.whitelisted-tld-test.mil\n" >> out_raw.txt
    {
        printf "whitelisted_tld,whitelisted-tld-test.gov.us\n"
        printf "whitelisted_tld,whitelisted-tld-test.edu\n"
        printf "whitelisted_tld,whitelisted-tld-test.mil\n"
        printf "blacklist,blacklisted.whitelisted-tld-test.mil\n"
    } >> out_log.txt

    # The validate script does not add whitelisted TLDs to the review config file
    [[ "$script_to_test" == 'validate' ]] && return
    {
        printf "ScamAdviser,whitelisted-tld-test.gov.us,whitelisted_tld,,\n"
        printf "ScamAdviser,whitelisted-tld-test.edu,whitelisted_tld,,\n"
        printf "ScamAdviser,whitelisted-tld-test.mil,whitelisted_tld,,\n"
    } >> out_review_config.txt
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
            printf "invalid-test.com/subfolder\n"
            printf "invalid-test-.com\n"
            printf "i.com\n"
        } >> data/pending/ScamAdviser.tmp

        # EXPECTED OUTPUT

        # The retrieval script saves invalid entries including subdomains to
        # the manual review file
        {
            printf "www.invalid-test-com\n"
            printf "100.100.100.1\n"
            printf "invalid-test.x\n"
            printf "invalid-test.100\n"
            printf "invalid-test.1x\n"
            printf "invalid-test.com/subfolder\n"
            printf "invalid-test-.com\n"
            printf "i.com\n"
        } >> out_manual_review.txt

        # Subdomains should not be included in the review config file
        {
            printf "ScamAdviser,invalid-test-com,invalid,,\n"
            printf "ScamAdviser,100.100.100.1,invalid,,\n"
            printf "ScamAdviser,invalid-test.x,invalid,,\n"
            printf "ScamAdviser,invalid-test.100,invalid,,\n"
            printf "ScamAdviser,invalid-test.1x,invalid,,\n"
            printf "ScamAdviser,invalid-test.com/subfolder,invalid,,\n"
            printf "ScamAdviser,invalid-test-.com,invalid,,\n"
            printf "ScamAdviser,i.com,invalid,,\n"
        } >> out_review_config.txt

        printf "invalid-test.xn--903fds\n" >> out_raw.txt

        {
            printf "invalid,invalid-test-com,ScamAdviser\n"
            printf "invalid,100.100.100.1,ScamAdviser\n"
            printf "invalid,invalid-test.x,ScamAdviser\n"
            printf "invalid,invalid-test.100,ScamAdviser\n"
            printf "invalid,invalid-test.1x,ScamAdviser\n"
            printf "invalid,invalid-test.com/subfolder,ScamAdviser\n"
            printf "invalid,invalid-test-.com,ScamAdviser\n"
            printf "invalid,i.com,ScamAdviser\n"
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
            printf "invalid-test.100\n"
            printf "invalid-test.1x\n"
            printf "invalid-test.com/subfolder\n"
            printf "invalid-test-.com\n"
            printf "i.com\n"
    } >> input.txt

    # EXPECTED OUTPUT
    # Note that invalid domains from the validation check are not added to the
    # review config file.

    printf "invalid-test.xn--903fds\n" >> out_raw.txt

    {
        printf "invalid,invalid-test-com,raw\n"
        printf "invalid,100.100.100.1,raw\n"
        printf "invalid,invalid-test.x,raw\n"
        printf "invalid,invalid-test.100,raw\n"
        printf "invalid,invalid-test.1x,raw\n"
        printf "invalid,invalid-test.com/subfolder,raw\n"
        printf "invalid,invalid-test-.com,raw\n"
        printf "invalid,i.com,raw\n"
    } >> out_log.txt
}

# TEST: checking of domains against toplist
test_toplist_check() {
    if [[ "$script_to_test" == 'retrieve' ]]; then
        # INPUT
        printf "microsoft.com\n" >> data/pending/ScamAdviser.tmp
        # EXPECTED OUTPUT
        printf "microsoft.com\n" >> out_manual_review.txt
        printf "ScamAdviser,microsoft.com,toplist,,\n" >> out_review_config.txt
        printf "toplist,microsoft.com,ScamAdviser\n" >> out_log.txt
        return
    fi

    # INPUT
    printf "microsoft.com\n" >> input.txt
    # EXPECTED OUTPUT
    # The validate script does not save invalid domains to manual review file
    printf "microsoft.com\n" >> out_raw.txt
    printf "raw,microsoft.com,toplist,,\n" >> out_review_config.txt
    printf "toplist,microsoft.com\n" >> out_log.txt
}

# TEST: exclusion of specific sources from light version
test_light_build() {
    # INPUT
    printf "raw-light-test.com\n" >> data/pending/Jeroengui.tmp
    # EXPECTED OUTPUT
    printf "raw-light-test.com\n" >> out_raw.txt
    # Domain from excluded source should not be in output
    grep -vxF "raw-light-test.com" out_raw.txt > out_raw_light.txt
}

### DEAD CHECK TESTS

# TEST: addition of resurrected domains
test_alive_check() {
    # INPUT
    printf "www.google.com\n" >> "$DEAD_DOMAINS"
    # EXPECTED OUTPUT
    # Subdomains should be kept to be processed by the validation check
    printf "www.google.com\n" >> out_raw.txt
    printf "resurrected_count,1,dead_domains_file\n" >> out_log.txt
}

# TEST: removal of dead domains
test_dead_check() {
    # INPUT
    {
        printf "apple.com\n"
        printf "abcdead-domain-test.com\n"
        printf "xyzdead-domain-test.com\n"
    } >> "$RAW"
    printf "abcdead-domain-test.com\n" >> "$ROOT_DOMAINS"
    printf "www.abcdead-domain-test.com\n" >> "$SUBDOMAINS"
    # EXPECTED OUTPUT
    printf "apple.com\n" >> out_raw.txt
    # Subdomains should be kept to be processed by the validation check
    printf "www.abcdead-domain-test.com\n" >> out_dead.txt
    printf "xyzdead-domain-test.com\n" >> out_dead.txt
    # dead count is 102 because of the placeholder lines
    printf "dead_count,102,raw\n" >> out_log.txt
    # Both files should be empty (all dead)
    : > out_subdomains.txt
    : > out_root_domains.txt
}

### PARKED CHECK TESTS

# TEST: addition of unparked domains
test_unparked_check() {
    # INPUT
    printf "www.github.com\n" >> "$PARKED_DOMAINS"
    printf "parked-errored-test.com\n" >> "$PARKED_DOMAINS"
    # EXPECTED OUTPUT
    # Subdomains should be kept to be processed by the validation check
    printf "www.github.com\n" >> out_raw.txt
    # Domains that errored during curl should be assumed to be still parked
    printf "parked-errored-test.com\n" >> out_parked.txt
    printf "unparked_count,1,parked_domains_file\n" >> out_log.txt
}

# TEST: removal of parked domains
test_parked_check() {
    # INPUT
    printf "apple.com\n" >> "$RAW"
    # Subfolder used here for easier testing despite being an invalid entry
    printf "porkbun.com/parked\n" >> "$RAW"
    printf "porkbun.com/parked\n" >> "$ROOT_DOMAINS"
    printf "www.porkbun.com/parked\n" >> "$SUBDOMAINS"
    # EXPECTED OUTPUT
    printf "apple.com\n" >> out_raw.txt
    # Subdomains should be kept to be processed by the validation check
    printf "www.porkbun.com/parked\n" >> out_parked.txt
    printf "parked_count,1,raw\n" >> out_log.txt
    # Both files should be empty (all parked)
    : > out_subdomains.txt
    : > out_root_domains.txt
}

### END OF 'test_<process>' functions

# Execute the script passed by the caller and check the exit status.
# Input:
#   $1: script to execute
#   $2: arguments to pass to script
run_script() {
    local errored

    echo ""
    echo "----------------------------------------------------------------------"
    printf "\e[1m[start] %s %s\e[0m\n" "$1" "$2"
    echo "----------------------------------------------------------------------"

    # Run script
    bash "scripts/${1}" "$2" || errored=true

    echo "----------------------------------------------------------------------"

    # Return if script had no errors
    [[ "$errored" != true ]] && return

    printf "\e[1m[warn] Script returned with an error\e[0m\n\n" >&2
    error=true
}

# Check if the test should exit with an exit status of 1 or 0.
check_and_exit() {
    local log_error

    # Check that all temporary files have been deleted after the run
    if ls x?? &> /dev/null || ls ./*.tmp &> /dev/null; then
        {
            printf "\e[1m[warn] Temporary files were not removed:\e[0m\n"
            ls x?? ./*.tmp 2> /dev/null
            printf "\n"
        } >&2

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

# Check that a file contains all the given terms.
# Input:
#   $1: file to check
#   $2: file with terms to check for
#   $3: name of file to check
# Output:
#   return 1 (if one or more terms not found)
check_terms() {
    local term_error

    while read -r term; do
        if ! grep -qF "$term" "$1"; then
            term_error=true
            break
        fi
    done < "$2"

    # Return if all terms found
    [[ "$term_error" != true ]] && return

    {
        printf "\e[1m[warn] %s is not as expected:\e[0m\n" "$3"
        cat "$1"
        printf "\n[info] Terms expected:\n"
        cat "$2"
        printf "\n"
    } >&2

    error=true

    return 1
}

# Compare the input file with the expected output file and print a warning if
# they are not the same.
#   $1: input file
#   $2: expected output file
#   $3: name of the file being checked
check_output() {
    sort "$1" -o "$1"
    sort "$2" -o "$2"
    cmp -s "$1" "$2" && return  # Return if files are the same
    {
        printf "\e[1m[warn] %s file is not as expected:\e[0m\n" "$3"
        cat "$1"
        printf "\n[info] Expected output:\n"
        cat "$2"
        printf "\n"
    } >&2

    error=true
}

# Entry point

set -e

# Do not allow running locally
[[ "$CI" == true ]] && main "$1"

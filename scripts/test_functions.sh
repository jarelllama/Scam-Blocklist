#!/bin/bash

# This script is used to test the other scripts in this project. Most tests
# consist of an input file that is processed by the called script and an output
# file that contains the expected results after processing. The output file is
# compared against the actual output file of the called script to determine if
# the results match.

readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly BLACKLIST='config/blacklist.txt'
readonly DOMAIN_LOG='config/domain_log.csv'
readonly REVIEW_CONFIG='config/review_config.csv'
readonly SOURCES='config/sources.csv'
readonly SOURCE_LOG='config/source_log.csv'
readonly WHITELIST='config/whitelist.txt'
readonly WILDCARDS='config/wildcards.txt'
readonly ADBLOCK='lists/adblock'
readonly DOMAINS='lists/wildcard_domains'

main() {
    # Initialize data directory
    local file
    for file in data/*.txt; do
        : > "$file"
    done

    # Initialize config directory
    local config
    for config in "$BLACKLIST" "$DOMAIN_LOG" "$REVIEW_CONFIG" "$SOURCE_LOG" \
        "$WILDCARDS"; do
        if [[ "$config" == *.csv ]]; then
            # Keep headers in the CSV files
            sed -i '1q' "$config"
            continue
        fi

        : > "$config"
    done

    # The ShellCheck test checks the whitelist file
    if [[ "$1" != 'shellcheck' ]]; then
        : > "$WHITELIST"
    fi

    error=false

    case "$1" in
        retrieve)
            TEST_RETRIEVE_VALIDATE "$1"
            ;;
        validate)
            TEST_RETRIEVE_VALIDATE "$1"
            ;;
        dead)
            TEST_DEAD_CHECK
            ;;
        parked)
            TEST_PARKED_CHECK
            ;;
        build)
            TEST_BUILD
            ;;
        shellcheck)
            SHELLCHECK
            ;;
        *)
            error 'No tests to run.'
            ;;
    esac
}

# Run ShellCheck for all scripts along with checks for common errors and
# mistakes.
SHELLCHECK() {
    local url script files

    printf "\e[1m[start] ShellCheck\e[0m\n"

    # Install ShellCheck
    url='https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.linux.x86_64.tar.xz'
    curl -sSL --retry 2 --retry-all-errors "$url" | tar -xJ

    # Check that ShellCheck was successfully installed
    shellcheck-stable/shellcheck --version || error 'ShellCheck did not install successfully.'

    # Run ShellCheck for each script
    for script in scripts/*.sh; do
        shellcheck-stable/shellcheck "$script" || error=true
    done

    # Check for carriage return characters
    if files="$(grep -rl $'\r' --exclude-dir={.git,shellcheck-stable} .)"; then
        printf "\n\e[1m[warn] Lines with carriage return characters:\e[0m\n" >&2
        printf "%s\n" "$files" >&2
        error=true
    fi

    # Check for missing space before comments excluding in CSV files
    if files="$(grep -rn '\S\s#\s' --exclude-dir={.git,shellcheck-stable} \
        --exclude=*.csv .)"; then
        printf "\n\e[1m[warn] Lines with missing space before comments:\e[0m\n" >&2
        printf "%s\n" "$files" >&2
        error=true
    fi

    # Check for unescaped periods in the whitelist
    if lines="$(grep -E '(^|[^\])\.' "$WHITELIST")"; then
        printf "\n\e[1m[warn] Unescaped periods found in the whitelist:\e[0m\n" >&2
        printf "%s\n" "$lines" >&2
        error=true
    fi

    [[ "$error" == true ]] && exit 1

    printf "\e[1m[success] Test completed. No errors found.\e[0m\n"
}

# Test the retrieval or validation scripts.
# Input:
#   $1 script to test ('retrieve' or 'validate')
TEST_RETRIEVE_VALIDATE() {
    local script_to_test="$1"

    # Initialize pending directory
    [[ -d data/pending ]] && rm -r data/pending
    mkdir -p data/pending

    test_review_file
    test_punycode_conversion
    test_invalid_removal
    test_whitelist_blacklist
    test_whitelisted_tld_removal
    test_toplist_check

    if [[ "$script_to_test" == 'retrieve' ]]; then
        test_large_source_error
        test_manual_addition_and_logging
        test_url_conversion
        test_known_dead_removal
        test_known_parked_removal
        test_light_build

        # Distribute the test input into various sources
        split -n l/3 input.txt
        mv xaa data/pending/Artists_Against_419.tmp
        mv xab data/pending/google_search_search-term-1.tmp
        mv xac data/pending/google_search_search-term-2.tmp

        # Enable all sources in the sources config file
        mawk '
            BEGIN { FS = OFS= "," }
            NR == 1 { print }
            NR > 1 {
                $4 = "y"
                print
            }' "$SOURCES" > temp
        mv temp "$SOURCES"

        # Run retrieval script
        run_script retrieve_domains.sh

    elif [[ "$script_to_test" == 'validate' ]]; then
        # Prepare sample raw files for processing
        cp input.txt "$RAW"
        cp input.txt "$RAW_LIGHT"

        # Run validation script
        run_script validate_domains.sh
    fi

    check_output
}

# Test the removal and addition of dead and resurrected domains respectively.
TEST_DEAD_CHECK() {
    # Generate placeholders
    # (split does not work well without enough lines)
    local i
    for i in {1..50};do
        input "placeholder483${i}s.com"
    done

    for i in {51..100};do
        input "placeholder483${i}s.com" "$DEAD_DOMAINS"
    done

    test_alive_check
    test_dead_check

    # Prepare sample raw files for processing
    cp input.txt "$RAW"
    cp input.txt "$RAW_LIGHT"

    # Run script
    run_script check_dead.sh checkalive
    run_script check_dead.sh part1
    run_script check_dead.sh part2
    run_script check_dead.sh remove

    # Remove placeholder lines
    local file
    for file in "$RAW" "$RAW_LIGHT" "$DEAD_DOMAINS" "$DOMAIN_LOG"; do
        mawk '!/^placeholder/' "$file" > temp
        mv temp "$file"
    done

    check_output
}

# Test the removal and addition of parked and unparked domains respectively.
TEST_PARKED_CHECK() {
    # Generate placeholders
    # (split does not work well without enough lines)
    local i
    for i in {1..100};do
        input "placeholder483${i}s.com"
    done

    for i in {101..200};do
        input "placeholder483${i}s.com" "$PARKED_DOMAINS"
    done

    test_unparked_check
    test_parked_check

    # Prepare sample raw files for processing
    cp input.txt "$RAW"
    cp input.txt "$RAW_LIGHT"

    # Run script
    run_script check_parked.sh checkunparked
    run_script check_parked.sh part1
    run_script check_parked.sh part2
    run_script check_parked.sh remove

    # Remove placeholder lines
    local file
    for file in "$RAW" "$RAW_LIGHT" "$PARKED_DOMAINS" "$DOMAIN_LOG"; do
        mawk '!/^placeholder/' "$file" > temp
        mv temp "$file"
    done

    check_output
}

# Test that the various formats of blocklists are built correctly.
TEST_BUILD() {
    test_wildcards_file
    test_adding_blacklisted
    test_blocklist_build

    # Run script
    run_script build_lists.sh

    # Remove comments from the resulting blocklists for easier checking against
    # the expected results files (keeps Adblock Plus header)
    local blocklist
    for blocklist in lists/*/*.txt; do
        sed -i '/[#!]/d' "$blocklist"
    done

    check_output
}

### RETRIEVAL/VALIDATION TESTS

# Test adding entries to the whitelist and blacklist via the review config file
test_review_file() {
    input Source,review-file-test.com,toplist,, "$REVIEW_CONFIG"
    input Source,review-file-misconfigured-test.com,toplist,y,y "$REVIEW_CONFIG"
    input Source,review-file-blacklist-test.com,toplist,y, "$REVIEW_CONFIG"
    input Source,review-file-whitelist-test.com,toplist,,y "$REVIEW_CONFIG"

    # Only unconfigured/misconfigured entries should remain in the review config file
    output Source,review-file-test.com,toplist,, "$REVIEW_CONFIG"
    output Source,review-file-misconfigured-test.com,toplist,y,y "$REVIEW_CONFIG"

    output review-file-blacklist-test.com "$BLACKLIST"
    output '^review-file-whitelist-test\.com$' "$WHITELIST"
}

# Test error handling from unusually large sources
test_large_source_error() {
    local entries
    entries="$(for i in {1..10001}; do printf "x%s.com\n" "$i"; done)"
    input "$entries" data/pending/Gridinsoft.tmp
    output ',Gridinsoft,,10001,0,0,0,0,0,,ERROR: too_large' "$SOURCE_LOG"
    output "$entries" data/pending/Gridinsoft.tmp
}

# Test manual addition of domains from repo issue, proper logging into domain
# log, source log, review config file, and additions to the manual review file
test_manual_addition_and_logging() {
    input www.manual-addition-test.com data/pending/Manual.tmp
    input m.-invalid-logging-test data/pending/Manual.tmp
    output www.manual-addition-test.com "$RAW"
    output www.manual-addition-test.com "$RAW_LIGHT"
    output ,Manual,,2,1,0,0,0,0,,saved "$SOURCE_LOG"
    output ,saved,www.manual-addition-test.com,Manual "$DOMAIN_LOG"
    output ,invalid,m.-invalid-logging-test,Manual "$DOMAIN_LOG"
    output Manual,m.-invalid-logging-test,invalid,, "$REVIEW_CONFIG"
    # Test additions to the manual review file
    output m.-invalid-logging-test data/pending/Manual.tmp
}

# Test conversion of URLs to domains and removal of square brackets
test_url_conversion() {
    input https://conversion-test[.]com[.]us
    input http://conversion-test-2.com
    output conversion-test.com.us "$RAW"
    output conversion-test-2.com "$RAW"
    output conversion-test.com.us "$RAW_LIGHT"
    output conversion-test-2.com "$RAW_LIGHT"
}

# Test removal of invalid entries
test_invalid_removal() {
    input 100.100.100.100
    input invalid-test.com/subfolder
    input '-invalid-test.com'
    input invalid-test-.com
    input invalid-.test.com
    input invalid.-test.com
    # Test that invalid TLDs are not allowed
    input invalid-test.-com
    input invalid-test.com-
    input invalid-test.1com
    input invalid-test.c
    # Test that single character subdomains are allowed
    input 1.invalid-test.com
    # Test that Punycode is allowed in the TLD
    input invalid-test.xn--903fds

    output invalid-test.xn--903fds "$RAW"
    output 1.invalid-test.com "$RAW"
    output invalid-test.xn--903fds "$RAW_LIGHT"
    output 1.invalid-test.com "$RAW_LIGHT"
    output invalid,100.100.100.100 "$DOMAIN_LOG"
    output invalid,invalid-test.com/subfolder "$DOMAIN_LOG"
    output invalid,-invalid-test.com "$DOMAIN_LOG"
    output invalid,invalid-test-.com "$DOMAIN_LOG"
    output invalid,invalid-.test.com "$DOMAIN_LOG"
    output invalid,invalid.-test.com "$DOMAIN_LOG"
    output invalid,invalid-test.-com "$DOMAIN_LOG"
    output invalid,invalid-test.com- "$DOMAIN_LOG"
    output invalid,invalid-test.1com "$DOMAIN_LOG"
    output invalid,invalid-test.c "$DOMAIN_LOG"

    # The validate script does not add invalid entries to the review config
    # file
    [[ "$script_to_test" == 'validate' ]] && return
    output 100.100.100.100,invalid "$REVIEW_CONFIG"
    output invalid-test.com/subfolder,invalid "$REVIEW_CONFIG"
    output -invalid-test.com,invalid "$REVIEW_CONFIG"
    output invalid-test-.com,invalid "$REVIEW_CONFIG"
    output invalid-.test.com,invalid "$REVIEW_CONFIG"
    output invalid.-test.com,invalid "$REVIEW_CONFIG"
    output invalid-test.-com,invalid "$REVIEW_CONFIG"
    output invalid-test.com-,invalid "$REVIEW_CONFIG"
    output invalid-test.1com,invalid "$REVIEW_CONFIG"
    output invalid-test.c,invalid "$REVIEW_CONFIG"

}

# Test conversion of Unicode to Punycode
test_punycode_conversion() {
    input 'ⴰⵣⵓⵍ.punycode-converstion-test.ⴰⵣⵓⵍ'
    # Test that entries that may cause idn2 to error are handled
    input pu--nycode-conversion-test.com

    output xn--4lj0cra7d.punycode-converstion-test.xn--4lj0cra7d "$RAW"
    output pu--nycode-conversion-test.com "$RAW"
    output xn--4lj0cra7d.punycode-converstion-test.xn--4lj0cra7d "$RAW_LIGHT"
    output pu--nycode-conversion-test.com "$RAW_LIGHT"
}

# Test removal of known dead domains
test_known_dead_removal() {
    input www.known-dead-test.com "$DEAD_DOMAINS"
    input www.known-dead-test.com
    output '' "$RAW"
    output '' "$RAW_LIGHT"
}

# Test removal of known parked domains
test_known_parked_removal() {
    input www.known-parked-test.com "$PARKED_DOMAINS"
    input www.known-parked-test.com
    output '' "$RAW"
    output '' "$RAW_LIGHT"
}

# Test whitelisting and blacklisting entries
test_whitelist_blacklist() {
    input '(regex-test)?\.whitelist-test\.com' "$WHITELIST"
    input blacklisted.whitelist-test.com "$BLACKLIST"
    # Test that the whitelist uses regex matching
    input regex-test.whitelist-test.com
    # Test that the blacklist matches subdomains
    input www.blacklisted.whitelist-test.com

    output '(regex-test)?\.whitelist-test\.com' "$WHITELIST"
    output blacklisted.whitelist-test.com "$BLACKLIST"
    output www.blacklisted.whitelist-test.com "$RAW"
    output www.blacklisted.whitelist-test.com "$RAW_LIGHT"
    output whitelist,regex-test.whitelist-test.com "$DOMAIN_LOG"

    # The validate script does not log blacklisted domains
    [[ "$script_to_test" == 'validate' ]] && return
    output blacklist,www.blacklisted.whitelist-test.com "$DOMAIN_LOG"
}

# Test removal of domains with whitelisted TLDs
test_whitelisted_tld_removal() {
    input whitelisted-tld-test.gov.us
    input whitelisted-tld-test.edu
    input whitelisted-tld-test.mil
    input blacklisted.whitelisted-tld-test.mil "$BLACKLIST"
    input blacklisted.whitelisted-tld-test.mil

    output blacklisted.whitelisted-tld-test.mil "$BLACKLIST"
    output blacklisted.whitelisted-tld-test.mil "$RAW"
    output blacklisted.whitelisted-tld-test.mil "$RAW_LIGHT"
    output whitelisted_tld,whitelisted-tld-test.gov.us "$DOMAIN_LOG"
    output whitelisted_tld,whitelisted-tld-test.edu "$DOMAIN_LOG"
    output whitelisted_tld,whitelisted-tld-test.mil "$DOMAIN_LOG"

    # The validate script does not log blacklisted domains and add whitelisted
    # TLDs to the review config file
    [[ "$script_to_test" == 'validate' ]] && return
    output blacklist,blacklisted.whitelisted-tld-test.mil "$DOMAIN_LOG"
    output whitelisted-tld-test.gov.us,whitelisted_tld "$REVIEW_CONFIG"
    output whitelisted-tld-test.edu,whitelisted_tld "$REVIEW_CONFIG"
    output whitelisted-tld-test.mil,whitelisted_tld "$REVIEW_CONFIG"
}

# Test checking of domains against toplist
test_toplist_check() {
    input www.microsoft.com
    input apple.com "$BLACKLIST"
    input apple.com

    output apple.com "$BLACKLIST"
    output apple.com "$RAW"
    output apple.com "$RAW_LIGHT"
    output microsoft.com,toplist "$REVIEW_CONFIG"
    output toplist,www.microsoft.com "$DOMAIN_LOG"
    # The retrieve script logs blacklisted domains
    if [[ "$script_to_test" == 'retrieve' ]]; then
        output blacklist,apple.com "$DOMAIN_LOG"
        return
    fi
    # The validate script does not remove domains in the toplist from the
    # raw files
    output www.microsoft.com "$RAW"
    output www.microsoft.com "$RAW_LIGHT"
}

# Test exclusion of specific sources from light version
test_light_build() {
    input raw-light-test.com data/pending/Jeroengui.tmp
    output raw-light-test.com "$RAW"
    output '' "$RAW_LIGHT"
}

### DEAD CHECK TESTS

# Test addition of resurrected domains
test_alive_check() {
    input google.com "$DEAD_DOMAINS"
    input xyzdead-domain-test.com "$DEAD_DOMAINS"
    output google.com "$RAW"
    # Resurrected domains should not be added to the light version
    output '' "$RAW_LIGHT"
    output xyzdead-domain-test.com "$DEAD_DOMAINS"
    output resurrected_count,1,dead_domains_file "$DOMAIN_LOG"
}

# Test removal of dead domains
test_dead_check() {
    input apple.com
    input abcdead-domain-test.com
    output apple.com "$RAW"
    output apple.com "$RAW_LIGHT"
    output abcdead-domain-test.com "$DEAD_DOMAINS"
    # Dead count is 51 because of the placeholder lines
    output dead_count,51,raw "$DOMAIN_LOG"
}

### PARKED CHECK TESTS

# Test addition of unparked domains
test_unparked_check() {
    input github.com "$PARKED_DOMAINS"
    input parked-errored-test.com "$PARKED_DOMAINS"
    output github.com "$RAW"
    # Unparked domains should not be added to the light version
    output '' "$RAW_LIGHT"
    # Domains that errored during curl should be assumed to be still parked
    output parked-errored-test.com "$PARKED_DOMAINS"
    output unparked_count,1,parked_domains_file "$DOMAIN_LOG"
}

# Test removal of parked domains
test_parked_check() {
    input apple.com
    # Subfolder used here for easier testing despite being an invalid entry
    input porkbun.com/parked
    output apple.com "$RAW"
    output apple.com "$RAW_LIGHT"
    output porkbun.com/parked "$PARKED_DOMAINS"
    output parked_count,1,raw "$DOMAIN_LOG"
}

### BUILD TESTS

# Test updating wildcards file and adding wildcards to the blocklist
test_wildcards_file() {
    local input output list

    # x is appended to the subdomain to prevent getting removed by subdomain
    # removal.
    input="$({
        # Test that root domains that occur 10 times or more are added
        for i in {1..10}; do printf "x%s.wildcard.com\n" "$i"; done
        for i in {1..9}; do printf "x%s.root-domain.com\n" "$i"; done
        # Test that TLDs like 'com.us' should not be added
        for i in {1..10}; do printf "x%s.com.us\n" "$i"; done
        # Test that root domains found in the toplist are not added
        for i in {1..10}; do printf "x%s.google.com\n" "$i"; done
        # Test that root domains not found in the toplist but are whitelisted
        # are not added
        for i in {1..10}; do printf "x%s.whitelisted.com\n" "$i"; done
        # Test that existing wildcards are kept if they occur 10 times or more
        for i in {1..10}; do printf "x%s.existing-wildcard.apple.com\n" "$i"; done
        for i in {1..9}; do printf "x%s.old-existing-wildcard.github.com\n" "$i"; done
    })"
    input "$input" "$RAW"
    input '^whitelisted\.com$' "$WHITELIST"
    input existing-wildcard.apple.com "$WILDCARDS"
    input old-existing-wildcard.github.com "$WILDCARDS"

    # Domains that should not be removed via wildcard matching
    output="$({
        for i in {1..9}; do printf "x%s.root-domain.com\n" "$i"; done
        for i in {1..10}; do printf "x%s.com.us\n" "$i"; done
        for i in {1..10}; do printf "x%s.google.com\n" "$i"; done
        for i in {1..10}; do printf "x%s.whitelisted.com\n" "$i"; done
        for i in {1..9}; do printf "x%s.old-existing-wildcard.github.com\n" "$i"; done
    })"

    output "$(mawk '{ print "||" $0 "^" }' <<< "$output")" \
        "${ADBLOCK}/scams.txt"
    output "$output" "${DOMAINS}/scams.txt"
    output wildcard.com "$WILDCARDS"
    output existing-wildcard.apple.com "$WILDCARDS"

    for list in "${ADBLOCK}/scams.txt" "${ADBLOCK}/scams_light.txt"; do
        output '||wildcard.com^' "$list"
        output '||existing-wildcard.apple.com^' "$list"
    done

    for list in "${DOMAINS}/scams.txt" "${DOMAINS}/scams_light.txt"; do
        output wildcard.com "$list"
        output existing-wildcard.apple.com "$list"
    done
}

# Test adding blacklisted domains to the light version
test_adding_blacklisted() {
    input microsoft.com "$RAW"
    input microsoft.com "$BLACKLIST"

    local list
    for list in "${ADBLOCK}/scams.txt" "${ADBLOCK}/scams_light.txt"; do
        output '||microsoft.com^' "$list"
    done

    for list in "${DOMAINS}/scams.txt" "${DOMAINS}/scams_light.txt"; do
        output microsoft.com "$list"
    done
}

# Test building the blocklists
test_blocklist_build() {
    # Test that subdomains are removed
    input www.build-test.com "$RAW"
    input www.build-test.com "$RAW_LIGHT"
    input full-version-only.com "$RAW"

    output '||full-version-only.com^' "${ADBLOCK}/scams.txt"
    output 'full-version-only.com' "${DOMAINS}/scams.txt"

    local list
    for list in "${ADBLOCK}/scams.txt" "${ADBLOCK}/scams_light.txt"; do
        output '[Adblock Plus]' "$list"
        output '||build-test.com^' "$list"
    done

    for list in "${DOMAINS}/scams.txt" "${DOMAINS}/scams_light.txt"; do
        output build-test.com "$list"
    done

}

# Execute the called script and check the exit status.
# Input:
#   $1: script to execute
#   $2: arguments to pass to script
run_script() {
    local exit_status=0

    printf -- "\n----------------------------------------------------------------------\n"
    printf "\e[1m[start] %s %s\e[0m\n" "$1" "$2"
    printf -- "----------------------------------------------------------------------\n"

    # Run script
    bash "scripts/${1}" "$2" || exit_status=1

    printf -- "----------------------------------------------------------------------\n"

    # Return if script had no errors
    [[ "$exit_status" == 0 ]] && return

    printf "\e[1m[warn] Script returned with an error\e[0m\n\n" >&2
    error=true
}

# Compare the actual results file with the expected results file.
check_output() {
    while read -r actual_output_file; do
        local expected_output_file="${actual_output_file//\//_}.txt"
        local term_error=false

        if [[ ! -f "$actual_output_file" ]]; then
            error "${actual_output_file} is not found."
        elif [[ ! -f "$expected_output_file" ]]; then
            error "${expected_output_file} is not found."
        fi

        if [[ "$actual_output_file" == *.csv ]]; then
            # For CSV files, check for matching terms instead of entire file
            # content
            while read -r term; do
                if ! grep -qF -- "$term" "$actual_output_file"; then
                    term_error=true
                    break
                fi
            done < "$expected_output_file"

            # If all terms are matching, skip to next file to check
            [[ "$term_error" == false ]] && continue

        else
            # If files match, skip to next file to check
            if cmp -s <(sort "$actual_output_file") <(sort "$expected_output_file"); then
                continue
            fi
        fi

        {
            printf "\e[1m[warn] %s file is not as expected:\e[0m\n" "$actual_output_file"
            cat "$actual_output_file"
            printf "\n[info] Expected output:\n"
            cat "$expected_output_file"
            printf "\n"
        } >&2

        error=true

    done < output_files_to_test.txt

    # Check that all temporary files have been deleted after the run
    if ls x?? &> /dev/null || ls ./*.tmp &> /dev/null; then
        {
            printf "\e[1m[warn] Temporary files were not removed:\e[0m\n"
            ls x?? ./*.tmp 2> /dev/null || true
            printf "\n"
        } >&2

        error=true
    fi

    # Check if the tests were all completed successfully
    if [[ "$error" == false ]]; then
        printf "\e[1m[success] Test completed. No errors found.\e[0m\n\n"
    fi

    # Print source log for retrieval test
    if [[ "$script_to_test" == 'retrieve' ]]; then
        printf "Source log:\n%s\n\n" "$(<"$SOURCE_LOG")"
    fi

    [[ "$error" == true ]] && exit 1 || exit 0
}

# Add an entry into a file to be processed by the called script for testing.
# Input:
#   $1: Entry to add into file
#   $2: File to add entry into (default is input.txt)
input() {
    printf "%s\n" "$1" >> "${2:-input.txt}"
}

# Add an entry to an output file which is used as the expected results to
# compare against the actual results of the called script.
# Input:
#   $1: Entry to add into expected results file
#   $2: Actual results file path
output() {
    local expected_output="$1"
    local actual_output_file="$2"
    local expected_output_file="${actual_output_file//\//_}.txt"

    printf "%s\n" "$actual_output_file" >> output_files_to_test.txt
    # Remove duplicates without sorting
    mawk '!seen[$0]++' output_files_to_test.txt > temp
    mv temp output_files_to_test.txt

    # Always ensure the expected results file is created
    touch "$expected_output_file"

    [[ -z "$expected_output" ]] && return

    printf "%s\n" "$expected_output" >> "$expected_output_file"
}

# Print error message and exit.
# Input:
#   $1: error message to print
error() {
    printf "\n\e[1;31m%s\e[0m\n\n" "$1" >&2
    exit 1
}

# Entry point

set -e

# Do not allow running locally
[[ "$CI" != true ]] && error 'Running locally.'

main "$1"

#!/bin/bash

# This script is used to test the other scripts in this project. Most tests
# consist of an input file that is processed by the called script and an output
# file that contains the expected results after processing. The output file is
# compared against the actual output file of the called script to determine if
# the results match.

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly SOURCES='config/sources.csv'
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
    # Initialize data directory
    find data -type f -name "*.txt" -exec truncate -s 0 {} \;

    # Initialize config directory
    local config
    for config in "$BLACKLIST" "$DOMAIN_LOG" "$REVIEW_CONFIG" "$SOURCE_LOG" \
        "$WHITELIST" "$WILDCARDS"; do
        if [[ "$config" == *.csv ]]; then
            # Keep headers in the CSV files
            sed -i '1q' "$config"
            continue
        fi

        : > "$config"
    done

    error=false

    case "$1" in
        'retrieve')
            TEST_RETRIEVE_VALIDATE "$1"
            ;;
        'validate')
            TEST_RETRIEVE_VALIDATE "$1"
            ;;
        'dead')
            TEST_DEAD_CHECK
            ;;
        'parked')
            TEST_PARKED_CHECK
            ;;
        'build')
            TEST_BUILD
            ;;
        'shellcheck')
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
    local scripts script files

    printf "\e[1m[start] ShellCheck\e[0m\n"

    # Install ShellCheck
    local url='https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.linux.x86_64.tar.xz'
    curl -sSL "$url" | tar -xJ

    # Check that ShellCheck was successfully installed
    shellcheck-stable/shellcheck --version || error 'ShellCheck did not install successfully.'

    # Find scripts
    scripts=$(find . -type f -name "*.sh")

    [[ -z "$scripts" ]] && error 'No scripts found.'

    # Run ShellCheck for each script
    for script in $scripts; do
        shellcheck-stable/shellcheck "$script" || error=true
    done

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
        "$(wc -l <<< "$scripts")" "$scripts"

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

    test_punycode_conversion
    test_subdomain_removal
    test_review_file
    test_whitelist_blacklist
    test_whitelisted_tld_removal
    test_invalid_removal
    test_toplist_check

    if [[ "$script_to_test" == 'retrieve' ]]; then
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
    for i in {1..100};do
        input "placeholder483${i}s.com"
    done

    for i in {101..200};do
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
        mawk '!/^placeholder/' "$file" > temp || true
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
        mawk '!/^placeholder/' "$file" > temp || true
        mv temp "$file"
    done

    check_output
}

# Test that the various formats of blocklists are built correctly.
TEST_BUILD() {
    # Test full version
    input google.com "$RAW"
    input google.com "$BLACKLIST"
    input test.wildcard-test.com "$RAW"
    input full-version-only.com "$RAW"
    # Test light version
    # Note that google.com should be in the light version as it is in the
    # toplist and is blacklisted.
    input test.wildcard-test.com "$RAW_LIGHT"
    # Test removal of redundant entries via wildcard matching
    input wildcard-test.com "$WILDCARDS"

    # Adblock format full version
    output '[Adblock Plus]' "${ADBLOCK}/scams.txt"
    output '||google.com^' "${ADBLOCK}/scams.txt"
    output '||wildcard-test.com^' "${ADBLOCK}/scams.txt"
    output '||full-version-only.com^' "${ADBLOCK}/scams.txt"
    # Adblock format light version
    output '[Adblock Plus]' "${ADBLOCK}/scams_light.txt"
    output '||google.com^' "${ADBLOCK}/scams_light.txt"
    output '||wildcard-test.com^' "${ADBLOCK}/scams_light.txt"
    # Domains format full version
    output google.com "${DOMAINS}/scams.txt"
    output wildcard-test.com "${DOMAINS}/scams.txt"
    output full-version-only.com "${DOMAINS}/scams.txt"
    # Domains format light version
    output google.com "${DOMAINS}/scams_light.txt"
    output wildcard-test.com "${DOMAINS}/scams_light.txt"

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

# Test manual addition of domains from repo issue, proper logging into domain
# log, source log, review config file, and additions to the manual review file
test_manual_addition_and_logging() {
    input manual-addition-test.com data/pending/Manual.tmp
    input invalid-logging-test data/pending/Manual.tmp
    output manual-addition-test.com "$RAW"
    output manual-addition-test.com "$RAW_LIGHT"
    output ,Manual,,2,1,0,0,0,0,,saved "$SOURCE_LOG"
    output ,saved,manual-addition-test.com,Manual "$DOMAIN_LOG"
    output ,invalid,invalid-logging-test,Manual "$DOMAIN_LOG"
    output Manual,invalid-logging-test,invalid,, "$REVIEW_CONFIG"
    # Test additions to the manual review file
    output invalid-logging-test data/pending/Manual.tmp
}

# Test conversion of URLs to domains
# Test removal of square brackets
test_url_conversion() {
    input https://conversion-test[.]com[.]us
    input http://conversion-test-2.com
    output conversion-test.com.us "$RAW"
    output conversion-test-2.com "$RAW"
    output conversion-test.com.us "$RAW_LIGHT"
    output conversion-test-2.com "$RAW_LIGHT"
}

# Test conversion of Unicode to Punycode
test_punycode_conversion() {
    input 'ⴰⵣⵓⵍ.bortzmeyer.fr'
    # Test that entries that may cause idn2 to error are handled properly
    input pu--nycode-conversion-test.com

    output xn--4lj0cra7d.bortzmeyer.fr "$RAW"
    output pu--nycode-conversion-test.com "$RAW"
    output xn--4lj0cra7d.bortzmeyer.fr "$RAW_LIGHT"
    output pu--nycode-conversion-test.com "$RAW_LIGHT"
}

# Test removal of known dead domains including subdomains
test_known_dead_removal() {
    input www.known-dead-test.com "$DEAD_DOMAINS"
    input www.known-dead-test.com
    output '' "$RAW"
    output '' "$RAW_LIGHT"
}

# Test removal of known parked domains including subdomains
test_known_parked_removal() {
    input www.known-parked-test.com "$PARKED_DOMAINS"
    input www.known-parked-test.com
    output '' "$RAW"
    output '' "$RAW_LIGHT"
}

# Test removal of common subdomains
test_subdomain_removal() {
    while read -r subdomain; do
        subdomain="${subdomain}.subdomain-test.com"
        input "$subdomain"
        output "$subdomain" "$SUBDOMAINS"
    done < "$SUBDOMAINS_TO_REMOVE"

    output subdomain-test.com "$RAW"
    output subdomain-test.com "$RAW_LIGHT"
    output subdomain-test.com "$ROOT_DOMAINS"
}

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

# Test whitelisting and blacklisting entries
test_whitelist_blacklist() {
    input 'whitelist-test\.com' "$WHITELIST"
    input blacklisted.whitelist-test.com "$BLACKLIST"
    input blacklisted.whitelist-test.com
    # Test that the whitelist uses regex matching
    input regex-test.whitelist-test.com

    output 'whitelist-test\.com' "$WHITELIST"
    output blacklisted.whitelist-test.com "$BLACKLIST"
    output blacklisted.whitelist-test.com "$RAW"
    output blacklisted.whitelist-test.com "$RAW_LIGHT"
    output whitelist,regex-test.whitelist-test.com "$DOMAIN_LOG"

    # The validate script does not log blacklisted domains
    [[ "$script_to_test" == 'validate' ]] && return
    output blacklist,blacklisted.whitelist-test.com "$DOMAIN_LOG"
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

# Test removal of invalid entries
test_invalid_removal() {
    input 100.100.100.1
    input invalid-test.x
    input invalid-test.100
    input invalid-test.1x
    input invalid-test.com/subfolder
    input invalid-test-.com
    input i.com
    # Test that invalid subdomains/root domains are not added into the
    # subdomains/root domains files
    input www.invalid-test-com
    # Test that punycode is allowed in the TLD
    input invalid-test.xn--903fds

    output '' "$SUBDOMAINS"
    output '' "$ROOT_DOMAINS"
    output invalid-test.xn--903fds "$RAW"
    output invalid-test.xn--903fds "$RAW_LIGHT"
    output invalid,invalid-test-com "$DOMAIN_LOG"
    output invalid,100.100.100.1 "$DOMAIN_LOG"
    output invalid,invalid-test.x "$DOMAIN_LOG"
    output invalid,invalid-test.100 "$DOMAIN_LOG"
    output invalid,invalid-test.1x "$DOMAIN_LOG"
    output invalid,invalid-test.com/subfolder "$DOMAIN_LOG"
    output invalid,invalid-test-.com "$DOMAIN_LOG"
    output invalid,i.com "$DOMAIN_LOG"

    # The validate script does not add invalid entries to the review config
    # file
    [[ "$script_to_test" == 'validate' ]] && return
    output invalid-test-com,invalid "$REVIEW_CONFIG"
    output 100.100.100.1,invalid "$REVIEW_CONFIG"
    output invalid-test.x,invalid "$REVIEW_CONFIG"
    output invalid-test.100,invalid "$REVIEW_CONFIG"
    output invalid-test.1x,invalid "$REVIEW_CONFIG"
    output invalid-test.com/subfolder,invalid "$REVIEW_CONFIG"
    output invalid-test-.com,invalid "$REVIEW_CONFIG"
    output i.com,invalid "$REVIEW_CONFIG"
}

# Test checking of domains against toplist
test_toplist_check() {
    input data.microsoft.com
    output data.microsoft.com,toplist "$REVIEW_CONFIG"
    output toplist,data.microsoft.com "$DOMAIN_LOG"
    # The validate script does not remove domains found in the toplist from the
    # raw file
    [[ "$script_to_test" == 'retrieve' ]] && return
    output data.microsoft.com "$RAW"
    output data.microsoft.com "$RAW_LIGHT"
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
    input www.google.com "$DEAD_DOMAINS"
    input xyzdead-domain-test.com "$DEAD_DOMAINS"
    # Subdomains should be kept to be processed by the validation check
    output www.google.com "$RAW"
    # Resurrected domains should not be added to the light version
    output '' "$RAW_LIGHT"
    output xyzdead-domain-test.com "$DEAD_DOMAINS"
    output resurrected_count,1,dead_domains_file "$DOMAIN_LOG"
}

# Test removal of dead domains
test_dead_check() {
    input apple.com
    input abcdead-domain-test.com
    # Dead domains should be removed from the subdomains/root domains files
    input www.abcdead-domain-test.com "$SUBDOMAINS"
    input abcdead-domain-test.com "$ROOT_DOMAINS"

    output apple.com "$RAW"
    output apple.com "$RAW_LIGHT"
    output '' "$SUBDOMAINS"
    output '' "$ROOT_DOMAINS"
    # Subdomains should be kept to be processed by the validation check
    output www.abcdead-domain-test.com "$DEAD_DOMAINS"
    # Dead count is 101 because of the placeholder lines
    output dead_count,101,raw "$DOMAIN_LOG"
}

### PARKED CHECK TESTS

# Test addition of unparked domains
test_unparked_check() {
    input www.github.com "$PARKED_DOMAINS"
    input parked-errored-test.com "$PARKED_DOMAINS"
    # Subdomains should be kept to be processed by the validation check
    output www.github.com "$RAW"
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
    # Parked domains should be removed from the subdomains/root domains files
    input www.porkbun.com/parked "$SUBDOMAINS"
    input porkbun.com/parked "$ROOT_DOMAINS"

    output apple.com "$RAW"
    output apple.com "$RAW_LIGHT"
    output '' "$SUBDOMAINS"
    output '' "$ROOT_DOMAINS"
    # Subdomains should be kept to be processed by the validation check
    output www.porkbun.com/parked "$PARKED_DOMAINS"
    output parked_count,1,raw "$DOMAIN_LOG"
}

# Execute the called script and check the exit status.
# Input:
#   $1: script to execute
#   $2: arguments to pass to script
run_script() {
    local exit_status=0

    echo ""
    echo "----------------------------------------------------------------------"
    printf "\e[1m[start] %s %s\e[0m\n" "$1" "$2"
    echo "----------------------------------------------------------------------"

    # Run script
    bash "scripts/${1}" "$2" || exit_status=1

    echo "----------------------------------------------------------------------"

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
                if ! grep -qF "$term" "$actual_output_file"; then
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

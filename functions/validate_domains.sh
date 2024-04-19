#!/bin/bash

# Validates the collated domains via a variety of checks and flags entries that
# require attention.

readonly FUNCTION='bash functions/tools.sh'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly WHITELIST='config/whitelist.txt'
readonly BLACKLIST='config/blacklist.txt'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'

# Function 'filter' logs the given entries and removes them from the raw file.
# Input:
#   $1: entries to process passed in a variable
#   $2: tag given to entries
#   --preserve: keep entries in the raw file
# Output:
#   filter_log.tmp (if filtered domains found)
filter() {
    local entries="$1"
    local tag="$2"

    # Return if no entries passed
    [[ -z "$entries" ]] && return

    if [[ "$3" != '--preserve' ]]; then
        # Remove entries from raw file
        comm -23 "$RAW" <(printf "%s" "$entries") > raw.tmp
        mv raw.tmp "$RAW"
    fi

    # Record entries into filter log
    mawk -v tag="$tag" '{print $0 " (" tag ")"}' <<< "$entries" \
        >> filter_log.tmp

    # Call shell wrapper to log entries into domain log
    $FUNCTION --log-domains "$entries" "$tag" raw
}

validate() {
    # Convert Unicode to Punycode in raw file and raw light file
    for file in "$RAW" "$RAW_LIGHT"; do
        # '--no-tld' in an attempt to fix
        # 'idn: tld_check_4z: Missing input' error
        idn --no-tld < "$file" | sort > temp
        mv temp "$file"
    done

    # Strip away subdomains
    while read -r subdomain; do  # Loop through common subdomains
        subdomains="$(mawk "/^${subdomain}\./" "$RAW")" || continue

        # Strip subdomains from raw file and raw light file
        sed -i "s/^${subdomain}\.//" "$RAW"
        sed -i "s/^${subdomain}\.//" "$RAW_LIGHT"

        # Save subdomains to be filtered later
        printf "%s\n" "$subdomains" >> subdomains.tmp

        # Save root domains to be filtered later
        printf "%s\n" "$subdomains" | sed "s/^${subdomain}\.//" >> root_domains.tmp

        filter "$subdomains" subdomain --preserve
    done < "$SUBDOMAINS_TO_REMOVE"
    sort -u "$RAW" -o "$RAW"
    sort -u "$RAW_LIGHT" -o "$RAW_LIGHT"

    # Remove whitelisted domains excluding blacklisted domains
    # Note whitelist matching uses keywords
    whitelisted="$(grep -Ff "$WHITELIST" "$RAW" | grep -vxFf "$BLACKLIST")"
    filter "$whitelisted" whitelist

    # Remove domains with whitelisted TLDs
    whitelisted_tld="$(grep -E '\.(gov|edu|mil)(\.[a-z]{2})?$' "$RAW")"
    filter "$whitelisted_tld" tld

    # Remove non-domain entries including IP addresses excluding punycode
    regex='^[[:alnum:].-]+\.[[:alnum:]-]*[a-z]{2,}[[:alnum:]-]*$'
    invalid="$(grep -vE "$regex" "$RAW")"
    filter "$invalid" invalid
    # The dead domains file is also checked here as invalid entries may get
    # picked up by the dead check and get saved in the dead cache.
    if invalid_dead="$(grep -vE "$regex" "$DEAD_DOMAINS")"; then
        grep -vxF "$invalid_dead" "$DEAD_DOMAINS" > dead.tmp
        mv dead.tmp "$DEAD_DOMAINS"
        mawk '{print $0 " (invalid)"}' <<< "$invalid_dead" >> filter_log.tmp
        $FUNCTION --log-domains "$invalid_dead" invalid dead_domains_file
    fi

    # Find domains in toplist excluding blacklisted domains
    # Note the toplist does not include subdomains
    in_toplist="$(comm -12 toplist.tmp "$RAW" | grep -vxFf "$BLACKLIST")"
    filter "$in_toplist" toplist --preserve

    # Return if no filtering done
    [[ ! -f filter_log.tmp ]] && return

    # Collate only filtered subdomains and root domains into the subdomains
    # file and root domains file
    if [[ -f root_domains.tmp ]]; then
        # Find root domains (subdomains stripped off) in the filtered raw file
        root_domains="$(comm -12 <(sort root_domains.tmp) "$RAW")"

        # Collate filtered root domains to exclude from dead check
        printf "%s\n" "$root_domains" >> "$ROOT_DOMAINS"
        sort -u "$ROOT_DOMAINS" -o "$ROOT_DOMAINS"

        # Collate filtered subdomains for dead check
        mawk "/\.${root_domains}$/" subdomains.tmp >> "$SUBDOMAINS"
        sort -u "$SUBDOMAINS" -o "$SUBDOMAINS"
    fi

    # Save changes to raw light file
    comm -12 "$RAW_LIGHT" "$RAW" > light.tmp
    mv light.tmp "$RAW_LIGHT"

    # Print filter log
    printf "\n\e[1mProblematic domains (%s):\e[0m\n" "$(wc -l < filter_log.tmp)"
    sed 's/(toplist)/& - \o033[31mmanual verification required\o033[0m/' filter_log.tmp

    # Do not notify for subdomains (the notifications got annoying)
    mawk '!/subdomain/' filter_log.tmp > temp
    mv temp filter_log.tmp

    [[ ! -s filter_log.tmp ]] && return

    # Call shell wrapper to send telegram notification
    $FUNCTION --send-telegram \
        "Problematic domains found during validation check:\n$(<filter_log.tmp)"

    printf "\nTelegram notification sent.\n"
}

# Entry point

trap 'find . -maxdepth 1 -type f -name "*.tmp" -delete' EXIT

$FUNCTION --format-all

# Download dependencies (done in parallel):
# Install idn (requires sudo) (note -qq does not seem to work here)
# Call shell wrapper to download toplist
{ command -v idn &> /dev/null || sudo apt-get install idn > /dev/null; } \
    & $FUNCTION --download-toplist
wait

validate

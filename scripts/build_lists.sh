#!/bin/bash

# Build and optimize the various formats of blocklists from the raw files.

readonly FUNCTION='bash scripts/tools.sh'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly SUBDOMAINS='config/subdomains.txt'
readonly WILDCARDS='config/wildcards.txt'
readonly ADBLOCK='lists/adblock'
readonly DOMAINS='lists/wildcard_domains'

main() {
    # Install AdGuard's Hostlist Compiler
    if ! command -v hostlist-compiler &> /dev/null; then
        npm install -g @adguard/hostlist-compiler > /dev/null
    fi

    $FUNCTION --download-toplist

    # Store whitelist and blacklist as a regex expression
    whitelist="$($FUNCTION --get-whitelist)"
    blacklist="$($FUNCTION --get-blacklist)"
    readonly whitelist blacklist

    # Update wildcards file
    {
        # Dynamically get new wildcards by finding root domains that appear 10
        # or more times that are in the toplist and are not whitelisted.
        # comm is faster than mawk when comparing lines.
        comm -23 <(mawk -F '.' '
            # Check length to avoid TLDs like 'com.us'
            length($(NF-1)) > 3 {
                # Increment count each time the root domain is found
                count[$(NF-1)"."$NF]++
            }
            END {
                for (domain in count) {
                    if (count[domain] >=10) {
                        print domain
                    }
                }
            }' "$RAW" | sort) toplist.tmp \
            | mawk -v whitelist="$whitelist" '$0 !~ whitelist'

        # Keep existing wildcards with subdomains as these tend to be manually
        # added. Only keep wildcards that occur 10 or more times. Using a while
        # loop here is faster than using mawk.
        while read -r wildcard; do
            [[ -z "$wildcard" ]] && break  # For when no wildcards are found
            if (( $(grep -c "$wildcard" "$RAW") >= 10 )); then
                printf "%s\n" "$wildcard"
            fi
        done <<< "$(mawk 'gsub(/\./, "&") >= 2' "$WILDCARDS")"

    } | sort -u -o "$WILDCARDS"

    # Add blacklisted domains in the full version that are in the toplist to
    # the light version.
    mawk -v blacklist="$blacklist" '
        NR==FNR {
            lines[$0]
            next
        } $0 in lines && $0 ~ blacklist
    ' "$RAW" toplist.tmp | sort -u - "$RAW_LIGHT" -o raw_light.tmp

    build '' "$RAW" scams.txt

    build 'LIGHT VERSION' raw_light.tmp scams_light.txt
}

# Process and compile the raw file into the various blocklist formats.
# Input:
#   $1: blocklist version name
#   $2: raw file
#   $3: output file
build() {
    local version="$1"
    local raw_file="$2"
    local output_file="$3"

    cp "$raw_file" source.tmp

    # Append wildcards to the raw file to optimize the number of entries.
    # The wildcards are not saved to the raw file as some of them do not
    # resolve and would be removed by the dead check.
    # Note that this adds the wildcards to the light version too.
    sort -u "$WILDCARDS" source.tmp -o source.tmp

    # Remove common subdomains to better make use of wildcard matching.
    mawk -v subdomains="$(mawk '{ print "^" $0 "\." }' \
        "$SUBDOMAINS" | paste -sd '|')" '{
        if ($0 ~ subdomains) {
            sub(subdomains, "")
        }
        print
    }' source.tmp | sort -u -o source.tmp

    # Compile blocklist. See the list of transformations here:
    # https://github.com/AdguardTeam/HostlistCompiler
    printf "\n"
    hostlist-compiler -i source.tmp -o compiled.tmp

    # Remove comments
    sed -i '/!/d' compiled.tmp

    # Build Adblock Plus format
    {
        printf "[Adblock Plus]\n"
        append_header '!' 'Adblock Plus'
        cat compiled.tmp
    } > "${ADBLOCK}/${output_file}"

    # Build Wildcard Domains format
    {
        append_header '#' 'Wildcard Domains'
        mawk '{ gsub (/[|^]/, ""); print }' compiled.tmp
    } > "${DOMAINS}/${output_file}"
}

# Append the header onto the blocklist.
# Input:
#   $1: comment character to use
#   $2: syntax of the blocklist
append_header() {
    cat << EOF
${1} Title: Jarelllama's Scam Blocklist ${version}
${1} Description: ${BLOCKLIST_DESCRIPTION}
${1} Homepage: https://github.com/jarelllama/Scam-Blocklist
${1} License: https://github.com/jarelllama/Scam-Blocklist/blob/main/LICENSE.md
${1} Version: $(date -u +"%m.%d.%H%M%S.%Y")
${1} Expires: 12 hours
${1} Last modified: $(date -u)
${1} Syntax: ${2}
${1} Number of entries: $(wc -l < compiled.tmp)
${1}
EOF
}

# Entry point

set -e

trap 'rm ./*.tmp temp 2> /dev/null || true' EXIT

$FUNCTION --format-files

main

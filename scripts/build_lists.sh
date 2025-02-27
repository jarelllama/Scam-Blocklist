#!/bin/bash

# Build the various formats of blocklists from the raw files.

readonly FUNCTION='bash scripts/tools.sh'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly ADBLOCK='lists/adblock'
readonly DOMAINS='lists/wildcard_domains'
readonly WILDCARDS='config/wildcards.txt'
readonly BLACKLIST='config/blacklist.txt'

main() {
    # Install AdGuard's Hostlist Compiler
    if ! command -v hostlist-compiler &> /dev/null; then
        npm install -g @adguard/hostlist-compiler > /dev/null
    fi

    $FUNCTION --download-toplist

    # Add domains found in the full version that are in the toplist and are
    # blacklisted into the light version.
    comm -12 "$RAW" <(comm -12 toplist.tmp "$BLACKLIST") \
        | sort -u - "$RAW_LIGHT" -o raw_light.tmp

    build '' "$RAW" scams.txt
    build 'LIGHT VERSION' raw_light.tmp scams_light.txt
}

# Remove redundant entries from the raw files and compile them into the various
# blocklist formats.
# Input:
#   $1: blocklist version name
#   $2: raw file
#   $3: output file
build() {
    local version="$1"
    local raw_file="$2"
    local output_file="$3"

    # Append wildcards to the raw file to optimize the number of entries.
    # The wildcards are not saved to the raw file as some of them do not
    # resolve and would be removed by the dead check.
    # Note that this adds the wildcards to the light version too.
    sort -u "$WILDCARDS" "$raw_file" -o source.tmp

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

$FUNCTION --format-all

main

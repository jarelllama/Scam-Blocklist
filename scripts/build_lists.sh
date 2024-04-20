#!/bin/bash

# Builds the various formats of blocklists from the raw files.

readonly FUNCTION='bash scripts/tools.sh'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly ADBLOCK='lists/adblock'
readonly DOMAINS='lists/wildcard_domains'

main() {
    # Install AdGuard's Hostlist Compiler
    if ! command -v hostlist-compiler &> /dev/null; then
        npm install -g @adguard/hostlist-compiler > /dev/null
    fi

    # Loop through the full and light blocklist versions
    for VERSION in '' 'LIGHT VERSION'; do
        if [[ "$VERSION" == '' ]]; then
            list='scams.txt'
            source="$RAW"
        else
            list='scams_light.txt'
            source="$RAW_LIGHT"
        fi

        build
    done
}

build() {
    # Compile list. See the list of transformations here:
    # https://github.com/AdguardTeam/HostlistCompiler
    hostlist-compiler -i "$source" -o compiled.tmp

    # Get entries, ignoring comments
    grep -F '||' compiled.tmp > temp
    mv temp compiled.tmp

    # Build Adblock Plus format
    printf "[Adblock Plus]\n" > "${ADBLOCK}/${list}"
    append_header '!' "$ADBLOCK" "Adblock Plus"
    cat compiled.tmp >> "${ADBLOCK}/${list}"

    # Build Wildcard Domains format
    : > "${DOMAINS}/${list}"
    append_header '#' "$DOMAINS" "Wildcard domains"
    sed 's/[\|^]//g' compiled.tmp >> "${DOMAINS}/${list}"
}

# Function 'append_header' appends the header onto the blocklist.
# Input:
#   $1: comment character to use
#   $2: directory of the blocklist to append to
#   $3: syntax of the blocklist
append_header() {
    cat << EOF >> "$2/${list}"
${1} Title: Jarelllama's Scam Blocklist ${VERSION}
${1} Description: ${BLOCKLIST_DESCRIPTION}
${1} Homepage: https://github.com/jarelllama/Scam-Blocklist
${1} License: https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md
${1} Version: $(date -u +"%m.%d.%H%M%S.%Y")
${1} Expires: 1 day
${1} Last modified: $(date -u)
${1} Syntax: ${3}
${1} Number of entries: $(wc -l < compiled.tmp)
${1}
EOF
}

# Entry point

trap 'find . -maxdepth 1 -type f -name "*.tmp" -delete' EXIT

$FUNCTION --format-all

main

#!/bin/bash
# This script builds the various formats of blocklists from the raw files.

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'

build_lists() {
    # Set default comment character to '#'
    [[ -z "$comment" ]] && comment='#'

    mkdir -p "lists/${directory}"

    # Loop through the full and light blocklist versions
    for i in {1..2}; do
        if [[ "$i" == '1' ]]; then
            version=''
            list_name='scams.txt'
            source_file="$RAW"
        elif [[ "$i" == '2' ]]; then
            version='LIGHT VERSION'
            list_name='scams_light.txt'
            source_file="$RAW_LIGHT"
        fi

        blocklist_path="lists/${directory}/${list_name}"

        # Append header onto blocklist
        cat << EOF > "$blocklist_path"
${comment} Title: Jarelllama's Scam Blocklist ${version}
${comment} Description: Blocklist for scam site domains automatically retrieved daily from Google Search and public databases.
${comment} Homepage: https://github.com/jarelllama/Scam-Blocklist
${comment} License: GNU GPLv3 (https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md)
${comment} Last modified: $(date -u)
${comment} Syntax: ${syntax}
${comment} Total number of entries: $(wc -l < "$source_file")
${comment}
EOF

        # Special case for Unbound format
        [[ "$syntax" == 'Unbound' ]] && printf "server:\n" >> "$blocklist_path"

        # Append formatted domains onto blocklist
        printf "%s\n" "$(awk -v before="$before" -v after="$after" \
            '{print before $0 after}' "$source_file")" >> "$blocklist_path"
    done
}

# Function 'format_file' is a shell wrapper to standardize the format of a file.
# $1: file to format
format_file() {
    bash functions/tools.sh format "$1"
}

# Build list functions are to specify the syntax of the lists for the build function.
# $syntax: name of list syntax
# $directory: directory to create list in
# $comment: character used for comments (blank defaults to '#')
# $before: characters to append before each domain
# $after: characters to append after each domain

build_adblock() {
    local syntax='Adblock Plus'
    local directory='adblock'
    local comment='!'
    local before='||'
    local after='^'
    build_lists
}

build_dnsmasq() {
    local syntax='Dnsmasq'
    local directory='dnsmasq'
    local comment=''
    local before='local=/'
    local after='/'
    build_lists
}

build_unbound() {
    local syntax='Unbound'
    local directory='unbound'
    local comment=''
    local before='local-zone: "'
    local after='." always_nxdomain'
    build_lists
}

build_wildcard_asterisk() {
    local syntax='Wildcard Asterisk'
    local directory='wildcard_asterisk'
    local comment=''
    local before='*.'
    local after=''
    build_lists
}

build_wildcard_domains() {
    local syntax='Wildcard Domains'
    local directory='wildcard_domains'
    local comment=''
    local before=''
    local after=''
    build_lists
}

# Entry point

for file in config/* data/*; do
    format_file "$file"
done

build_adblock
build_dnsmasq
build_unbound
build_wildcard_asterisk
build_wildcard_domains

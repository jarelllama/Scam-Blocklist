#!/bin/bash

# Builds the various formats of blocklists from the raw files.

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'

build() {
    # Set default comment character to '#'
    local comment=${comment:-#}

    mkdir -p "lists/${directory}"

    # Loop through the full and light blocklist versions
    for i in {1..2}; do
        if (( i == 2 )); then
            local version='LIGHT VERSION'
            local list_name='scams_light.txt'
            local source_file="$RAW_LIGHT"
        fi

        source_file="${source_file:-$RAW}"
        blocklist_path="lists/${directory}/${list_name:-scams.txt}"

        # Special case for Adblock Plus format
        [[ "$syntax" == 'Adblock Plus' ]] && printf "[Adblock Plus]\n" >> "$blocklist_path"

        append_header

        # Special case for Unbound format
        [[ "$syntax" == 'Unbound' ]] && printf "server:\n" >> "$blocklist_path"

        # Append formatted domains onto blocklist
        awk -v before="$before" -v after="$after" \
            '{print before $0 after}' "$source_file" >> "$blocklist_path"
    done
}

# Function 'append_header' appends the header onto the blocklist.
append_header() {
    cat << EOF >> "$blocklist_path"
${comment} Title: Jarelllama's Scam Blocklist ${version}
${comment} Description: ${BLOCKLIST_DESCRIPTION}
${comment} Homepage: https://github.com/jarelllama/Scam-Blocklist
${comment} License: GNU GPLv3 (https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md)
${comment} Last modified: $(date -u)
${comment} Syntax: ${syntax}
${comment} Total number of entries: $(wc -l < "$source_file")
${comment}
EOF
}

# The 'build_<format>' functions are to specify the syntax of the various
# list formats to be referenced by the 'build' function.
#   $syntax: name of list syntax
#   $directory: directory to create list in
#   $comment: character used for comments (defaults is '#')
#   $before: characters to append before each domain
#   $after: characters to append after each domain

build_adblock() {
    local syntax='Adblock Plus'
    local directory='adblock'
    local comment='!'
    local before='||'
    local after='^'
    build
}

build_dnsmasq() {
    local syntax='Dnsmasq'
    local directory='dnsmasq'
    local comment=''
    local before='local=/'
    local after='/'
    build
}

build_unbound() {
    local syntax='Unbound'
    local directory='unbound'
    local comment=''
    local before='local-zone: "'
    local after='." always_nxdomain'
    build
}

build_wildcard_asterisk() {
    local syntax='Wildcard Asterisk'
    local directory='wildcard_asterisk'
    local comment=''
    local before='*.'
    local after=''
    build
}

build_wildcard_domains() {
    local syntax='Wildcard Domains'
    local directory='wildcard_domains'
    local comment=''
    local before=''
    local after=''
    build
}

# Entry point

for file in config/* data/*; do
    bash functions/tools.sh format "$file"
done

build_adblock
build_dnsmasq
build_unbound
build_wildcard_asterisk
build_wildcard_domains

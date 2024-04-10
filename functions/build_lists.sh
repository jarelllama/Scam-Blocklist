#!/bin/bash

# Builds the various formats of blocklists from the raw files.

readonly FUNCTION='bash functions/tools.sh'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'

build() {
    # Set the default comment character to '#'
    local comment=${comment:-#}

    mkdir -p "lists/${directory}"

    # Loop through the full and light blocklist versions
    for version in '' 'LIGHT VERSION'; do

        if [[ "$version" == 'LIGHT VERSION' ]]; then
            list_name='scams_light.txt'
            source_file="$RAW_LIGHT"
        else
            list_name='scams.txt'
            source_file="$RAW"
        fi

        blocklist_path="lists/${directory}/${list_name}"

        : > "$blocklist_path"

        # Special case for Adblock Plus syntax
        if [[ "$syntax" == 'Adblock Plus' ]]; then
            printf "[Adblock Plus]\n" >> "$blocklist_path"
        fi

        append_header

        # Special case for Unbound syntax
        if [[ "$syntax" == 'Unbound' ]]; then
            printf "server:\n" >> "$blocklist_path"
        fi

        # Append formatted domains onto blocklist
        awk -v before="$before" -v after="$after" \
            '{print before $0 after}' "$source_file" >> "$blocklist_path"
    done
}

append_header() {
    cat << EOF >> "$blocklist_path"
${comment} Title: Jarelllama's Scam Blocklist ${version}
${comment} Description: ${BLOCKLIST_DESCRIPTION}
${comment} Homepage: https://github.com/jarelllama/Scam-Blocklist
${comment} License: https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md
${comment} Version: $(date -u +"%m.%d.%H%M%S.%Y")
${comment} Expires: 1 day
${comment} Last modified: $(date -u)
${comment} Syntax: ${syntax}
${comment} Number of entries: $(wc -l < "$source_file")
${comment}
EOF
}

# The 'build_<format>' functions are to specify the syntax of the various list
# formats to be referenced by the 'build' function.
#   $syntax: name of list syntax
#   $directory: directory to create list in
#   $comment: character used for comments (default is '#')
#   $before: characters to append before each domain (default is none)
#   $after: characters to append after each domain (default is none)

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

$FUNCTION --format-all

build_adblock
build_dnsmasq
build_unbound
build_wildcard_asterisk
build_wildcard_domains

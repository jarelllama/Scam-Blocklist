#!/bin/bash
raw_file='data/raw.txt'
raw_light_file='data/raw_light.txt'

function main {
    build_adblock
    build_dnsmasq
    build_unbound
    build_wildcard_asterisk
    build_wildcard_domains
}

function build_lists {
    [[ -z "$comment" ]] && comment='#'  # Set default comment to '#'
    mkdir -p "lists/${directory}"  # Create directory if not present

    # Loop through the two blocklist versions
    for i in {1..2}; do
        [[ "$i" -eq 1 ]] && { list_name='scams.txt'; version=''; source_file="$raw_file"; }
        [[ "$i" -eq 2 ]] && { list_name='scams_light.txt'; version='LIGHT VERSION'; source_file="$raw_light_file"; }
        blocklist_path="lists/${directory}/${list_name}"

        cat << EOF > "$blocklist_path"  # Append header onto blocklist
${comment} Title: Jarelllama's Scam Blocklist ${version}
${comment} Description: Blocklist for scam site domains automatically retrieved daily from Google Search and public databases.
${comment} Homepage: https://github.com/jarelllama/Scam-Blocklist
${comment} License: GNU GPLv3 (https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md)
${comment} Last modified: $(date -u)
${comment} Syntax: ${syntax}
${comment} Total number of entries: $(wc -l < "$source_file")
${comment}
EOF

        [[ "$syntax" == 'Unbound' ]] && printf "server:\n" >> "$blocklist_path"  # Special case for Unbound format
        # Append formatted domains onto blocklist
        printf "%s\n" "$(awk -v before="$before" -v after="$after" '{print before $0 after}' "$source_file")" >> "$blocklist_path"
    done
}

function format_list {
    bash functions/tools.sh "format" "$1"
}

function build_adblock {
    syntax='Adblock Plus' && directory='adblock' && comment='!' && before='||' && after='^'
    build_lists
}

function build_dnsmasq {
    syntax='Dnsmasq' && directory='dnsmasq' && comment='' && before='local=/' && after='/'
    build_lists
}

function build_unbound {
    syntax='Unbound' && directory='unbound' && comment='' && before='local-zone: "' && after='." always_nxdomain'
    build_lists
}

function build_wildcard_asterisk {
    syntax='Wildcard Asterisk' && directory='wildcard_asterisk' && comment='' && before='*.' && after=''
    build_lists
}

function build_wildcard_domains {
    syntax='Wildcard Domains' && directory='wildcard_domains' && comment='' && before='' && after=''
    build_lists
}

main

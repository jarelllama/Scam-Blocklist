#!/bin/bash

trap "find . -maxdepth 1 -type f -name '*.tmp' -delete" EXIT

if [[ "$#" -eq 0 ]]; then
    echo -e "No options provided"
    exit 1
fi

title="Jarelllama's Scam Blocklist"
description='Blocklist for scam sites automatically retrieved from Google Search'
expires='4'
comment='#'

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -i | --input)
            input="$2"
            ;;
        -o | --output)
            output="$2"
            ;;
        -t | --title)
            title="$2"
            ;;
        -d | --description)
            description="$2"
            ;;
        -e | --expires)
            expires="$2"
            ;;
        --adblock)
            syntax='Adblock Plus'
            path="lists/adblock/${output}"
            comment='!'
            before='||'
            after='^'
            ;;
        --dnsmasq)   
            syntax='Dnsmasq' 
            path="lists/dnsmasq/${output}"
            before='address=/'
            after='/#'
            ;;
        --unbound)       
            syntax='Unbound' 
            path="lists/unbound/${output}"
            before='local-zone: "'
            after='." always_nxdomain'
            ;;
        --wc-asterisk)
            syntax='Wildcard Asterisk' 
            path="lists/wildcard_asterisk/${output}"
            before='*.'
            after=''
            ;;
        --wc-domains)
            syntax='Wildcard Domains' 
            path="lists/wildcard_domains/${output}"
            before=''
            after=''
            ;;
        *)
            echo "Invalid option: --{$1}"
            exit 1
            ;;
    esac
    shift
done

if [[ -z "$input" ]]; then
    echo "No input file provided"
    exit 1
fi

if [[ -z "$output" ]]; then
    echo "No output file provided"
    exit 1
fi

if [[ -z "$syntax" ]]; then
    echo "No syntax provided"
    exit 1
fi

echo -e "\nBuilding ${syntax}..."

touch "$path"

awk -v before="$before" -v after="$after" \
    '{print before $0 after}' \
    "$input" > "${path}.tmp"

sort "${path}.tmp" -o "${path}.tmp"

[[ "$syntax" == 'Unbound' ]] \
    && sed -i '1s/^/server:\n/' "${path}.tmp"

grep -vE "^${comment}" "$path" > previous.tmp

if diff -q previous.tmp "${path}.tmp" >/dev/null; then
   echo "No changes."
   exit 0
fi

num_before=$(wc -l < previous.tmp)
num_after=$(wc -l < "${path}.tmp")
echo "Total entries before: ${num_before}"
echo "Difference: $((num_after - num_before))"
echo "Final entries after: ${num_after}"

echo "${comment} Title: ${title}
${comment} Description: ${description}
${comment} Homepage: https://github.com/jarelllama/Scam-Blocklist
${comment} License: GNU GPLv3 (https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md)
${comment} Version: $(date -u +"%m.%d.%H%M%S.%Y")
${comment} Last modified: $(date -u)
${comment} Expires: ${expires} hours
${comment} Syntax: ${syntax}
${comment} Total number of entries: ${num_after}
${comment}" | cat - "${path}.tmp" > "$path"

echo
git add "$path"
git commit -qm "Build ${syntax}"

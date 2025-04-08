#!/bin/bash

# Build the NSFW blocklist.

readonly FUNCTION='bash scripts/tools.sh'
readonly BLOCKLIST='lists/adblock/nsfw.txt'

# Patterns to match for
readonly -a TERMS=(
    \.sex$
    ^sex
    asiangalore
    blowjob
    brazzers
    camwhores
    dinotube
    escort
    fansly
    fapello
    gaymaletube
    gonewild
    hentai
    hookers
    hookup
    internetchicks
    jizz
    masterfap
    noodlemagazine
    onlyfans
    onlyleaks
    porn
    redtube
    rule34
    spankbang
    thenudebay
    thothd
    thothub
    thumbzilla
    tubesafari
    xgroovy
    xhamster
    xhopen
    xnxx
    xvideo
    xxx
)

# Whitelisted domains
readonly -a WHITELIST=(
    batteryhookup.com
    sexpistolsofficial.com
    1337xxx.to
)

main() {
    # Install AdGuard's Hostlist Compiler
    if ! command -v hostlist-compiler &> /dev/null; then
        npm install -g @adguard/hostlist-compiler > /dev/null
    fi

    $FUNCTION --download-toplist

    # Get matching domains in the toplist
    local term
    for term in "${TERMS[@]}"; do
        mawk "/${term}/" toplist.tmp
    done | sort -u -o raw.tmp

    # Remove whitelisted domains
    local white
    for white in "${WHITELIST[@]}"; do
        sed -i "/${white}/d" raw.tmp
    done

    # Compile blocklist
    hostlist-compiler -i raw.tmp -o compiled.tmp

    # Remove comments
    sed -i '/!/d' compiled.tmp

    # Append header
    cat << EOF > "$BLOCKLIST"
[Adblock Plus]
! Title: Jarelllama's NSFW Blocklist
! Description: Blocklist for NSFW domains automatically retrieved daily.
! Homepage: https://github.com/jarelllama/Scam-Blocklist#nsfw-blocklist
! License: https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md
! Version: $(date -u +"%m.%d.%H%M%S.%Y")
! Expires: 12 hours
! Last modified: $(date -u)
! Syntax: Adblock Plus
! Number of entries: $(wc -l < compiled.tmp)
!
EOF

    cat compiled.tmp >> "$BLOCKLIST"
}

# Entry point

set -e

trap 'rm ./*.tmp 2> /dev/null || true' EXIT

main

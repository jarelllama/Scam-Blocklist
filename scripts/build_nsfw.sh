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

    # Get matching domains in the toplist excluding whitelisted domains
    awk -v terms="$(IFS='|'; printf "%s" "${TERMS[*]}")" \
        -v whitelist="$(IFS='|'; printf "^(%s)$" "${WHITELIST[*]}")" '
        $0 ~ terms && $0 !~ whitelist' toplist.tmp | sort -u -o raw.tmp

    # Compile the blocklist
    printf "\n"
    hostlist-compiler -i raw.tmp -o compiled.tmp

    # Create the blocklist
    {
        # Append header
        cat << EOF
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

        # Addend entries excluding comments
        mawk '!/!/' compiled.tmp
    } > "$BLOCKLIST"
}

# Entry point

set -e

trap 'rm ./*.tmp 2> /dev/null || true' EXIT

main

#!/bin/bash

# Builds the NSFW blocklist. The build process is entirely self-contained in
# this script.

readonly FUNCTION='bash functions/tools.sh'
readonly BLOCKLIST='lists/adblock/nsfw.txt'

# Patterns to match for
readonly -a TERMS=(
    porn
    xxx
    spankbang
    xhamster
    xvideos
    onlyfans
    fansly
    hentai
    redtube
    internetchicks
    masterfap
    thothub
    onlyleaks
    thumbzilla
    fapello
    thenudebay
    gonewild
    thothd
    camwhores
    brazzers
    hookup
    ^sex
    \\.sex$
    escorts
    rule34
)

# Whitelisted domains
readonly -a WHITELIST=(
    batteryhookup.com
    sexpistolsofficial.com
    1337xxx.to
)

# Function 'build' retrieves domains from the Tranco toplist, adds them to the
# raw file, formats it, and removes dead domains.
build() {
    # Format raw file
    grep '||' "$BLOCKLIST" > raw.tmp
    sed -i 's/||//; s/\^//' raw.tmp

    # Remove already processed domains
    comm -23 toplist.tmp raw.tmp > temp
    mv temp toplist.tmp

    # Get matching domains in toplist
    for term in "${TERMS[@]}"; do
        mawk "/$term/" toplist.tmp >> domains.tmp
    done

    # Add new domains to raw file
    sort -u domains.tmp raw.tmp -o raw.tmp

    # Remove whitelisted domains
    for white in "${WHITELIST[@]}"; do
        sed -i "/$white/d" raw.tmp
    done

    # Format to Adblock Plus syntax
    sed -i 's/.*/||&^/' raw.tmp

    # Remove dead domains
    dead-domains-linter -a -i raw.tmp
}

# Function 'deploy' builds the blocklist in Adblock Plus syntax.
deploy() {
    cat << EOF > "$BLOCKLIST"
[Adblock Plus]
! Title: Jarelllama's NSFW Blocklist
! Description: Blocklist for NSFW domains automatically retrieved daily.
! Homepage: https://github.com/jarelllama/Scam-Blocklist#nsfw-blocklist
! License: https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md
! Version: $(date -u +"%m.%d.%H%M%S.%Y")
! Expires: 1 day
! Last modified: $(date -u)
! Syntax: Adblock Plus
! Number of entries: $(wc -l < raw.tmp)
!
EOF
    cat raw.tmp >> "$BLOCKLIST"
}

# Entry point

trap 'find . -maxdepth 1 -type f -name "*.tmp" -delete' EXIT

# Install AdGuard's Dead Domains Linter
if ! command -v dead-domains-linter &> /dev/null; then
    npm install -g @adguard/dead-domains-linter > /dev/null
fi

# Download the Tranco toplist
$FUNCTION --download-toplist

build

deploy

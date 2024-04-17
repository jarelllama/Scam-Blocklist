#!/bin/bash

# Builds the NSFW blocklist. The build process is entirely self-contained in
# this one script.

readonly FUNCTION='bash functions/tools.sh'
readonly BLOCKLIST='lists/adblock/nsfw.txt'

# Function 'build' retrieves domains from the Tranco toplist, adds them to the
# raw file, formats it, and removes dead domains.
build() {
    # Patterns to match for
    terms=(
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
        \.sex
    )

    # Format raw file
    grep '||' "$BLOCKLIST" > raw.tmp
    sed -i 's/||//; s/\^//' raw.tmp

    # Get new domains from toplist
    for term in "${terms[@]}"; do
        grep -E "$term" toplist.tmp >> domains.tmp
    done
    sort -u domains.tmp -o domains.tmp

    # Remove domains already in raw file
    comm -23 domains.tmp raw.tmp > temp
    mv temp domains.tmp

    # Log new domains
    $FUNCTION --log-domains domains.tmp nsfw toplist

    # Add new domains to raw file
    sort -u domains.tmp raw.tmp -o raw.tmp

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
! Description: Blocklist for NSFW content automatically retrieved daily.
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

#!/bin/bash
raw_file='data/raw.txt'
source_log='config/source_log.csv'
today="$(date -u +"%d-%m-%y")"
yesterday="$(date -ud "yesterday" +"%d-%m-%y")"

function main {
    command -v csvgrep &> /dev/null || pip install -q csvkit  # Install csvkit
    for file in config/* data/*; do  # Format files in the config and data directory
        format_list "$file"
    done
    build_adblock
    build_dnsmasq
    build_unbound
    build_wildcard_asterisk
    build_wildcard_domains
    update_readme
}

function update_readme {
    cat << EOF > README.md
# Jarelllama's Scam Blocklist
Blocklist for scam site domains automatically retrieved from Google Search and public databases updated daily at 00:30 UTC.
| Format | Syntax |
| --- | --- |
| [Adblock Plus](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/adblock/scams.txt) | \|\|scam.com^ |
| [Dnsmasq](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/dnsmasq/scams.txt) | local=/scam.com/ |
| [Unbound](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/unbound/scams.txt) | local-zone: "scam.com." always_nxdomain |
| [Wildcard Asterisk](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_asterisk/scams.txt) | \*.scam.com |
| [Wildcard Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_domains/scams.txt) | scam.com |

## Statistics
[![Retrieve domains](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/retrieve.yml/badge.svg)](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/retrieve.yml)
[![Check lists](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/check.yml/badge.svg)](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/check.yml)
[![Test functions](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/test.yml/badge.svg)](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/test.yml)
\`\`\`
Total domains: $(wc -l < "$raw_file")

Statistics for each source:

Today | Yesterday | Excluded | Source
$(print_stats "Google Search")
$(print_stats "aa419.org")
$(print_stats "dfpi.ca.gov")
$(print_stats "guntab.com")
$(print_stats "petscams.com")
$(print_stats "scam.delivery")
$(print_stats "scam.directory")
$(print_stats "scamadviser.com")
$(print_stats "stopgunscams.com")
$(print_stats)

*The Excluded % is of domains not included in the
 blocklist. Mostly dead and whitelisted domains.
*Only active sources are shown. See the full list of
 sources in SOURCES.md.
\`\`\`
All data retrieved are publicly available and can be viewed from their respective [sources](https://github.com/jarelllama/Scam-Blocklist/blob/main/SOURCES.md).

## Retrieving scam domains from Google Search
Google provides a [Search API](https://developers.google.com/custom-search/v1/introduction) to retrieve JSON-formatted results from Google Search. The script uses a list of search terms almost exclusively used in scam sites to retrieve domains. See the list of search terms here: [search_terms.csv](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/search_terms.csv)

#### Rationale
Scam sites often do not have a long lifespan; malicious domains may be replaced before they can be manually reported. By programmatically searching Google using paragraphs from real-world scam sites, new domains can be added as soon as Google crawls the site. This requires no manual reporting.

The list of search terms is proactively updated and is mostly sourced from investigating new scam site templates seen on [r/Scams](https://www.reddit.com/r/Scams/).

#### Limitations
The Google Custom Search JSON API only provides ~100 free search queries per day. This limits the number of search terms that can be employed a day.

Each search term is frequently benchmarked on its number of new domains and false positives. Underperforming search terms are disabled to optimize the number of queries made. The figures for each search term can be viewed here: [source_log.csv](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/source_log.csv)

> Queries made today: $(count "queries")

#### Regarding other sources
The full domain retrieval process for all sources can be viewed in the repository's code.

## Filtering process
- The domains collated from all sources are filtered against a whitelist (scam reporting sites, forums, vetted companies, etc.)
- The domains are checked against the [Tranco Top Sites Ranking](https://tranco-list.eu/) for potential false positives and flagged domains are vetted manually
- Redundant entries are removed via wildcard matching. For example, 'sub.spam.com' is a wildcard match of 'spam.com' and is, therefore, redundant and is removed. Many of these wildcard domains also happen to be malicious hosting sites
- Only domains are included in the blocklist. IP addresses are checked for resolving DNS records and URLs are stripped down to their domains

The full filtering process can be viewed in the repository's code.

## Dead domains
Dead domains are removed daily using [AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter). Note that domains acting as wildcards are excluded from this process.

Dead domains that have become resolving again are included back into the blocklist.

## Why the Hosts format is not supported
Malicious domains often have [wildcard DNS records](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/) that allow scammers to create large amounts of subdomain records, such as 'random-subdomain.scam.com'. Each subdomain can point to a separate scam site and collating them all would inflate the blocklist size. Therefore, only formats supporting wildcard matching are built.

## Sources
Moved to [SOURCES.md](https://github.com/jarelllama/Scam-Blocklist/blob/main/SOURCES.md).

## Resources
- [AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter): tool for checking Adblock rules for dead domains
- [Legality of web scraping](https://www.quinnemanuel.com/the-firm/publications/the-legal-landscape-of-web-scraping/): The law firm of Quinn Emanuel Urquhart & Sullivan's memoranda on web scraping
- [LinuxCommand's Coding Standards](https://linuxcommand.org/lc3_adv_standards.php): shell script coding standard
- [ShellCheck](https://github.com/koalaman/shellcheck): shell script static analysis tool
- [Tranco List](https://tranco-list.eu/): ranking of the top 1 million domains
- [who.is](https://who.is/): WHOIS and DNS lookup tool

## See also
- [Durablenapkin's Scam Blocklist](https://github.com/durablenapkin/scamblocklist)
- [Elliotwutingfeng's Global Anti-Scam Organization Blocklist](https://github.com/elliotwutingfeng/GlobalAntiScamOrg-blocklist)
- [Elliotwutingfeng's Inversion DNSBL Blocklist](https://github.com/elliotwutingfeng/Inversion-DNSBL-Blocklists)
- [Hagezi's DNS Blocklists](https://github.com/hagezi/dns-blocklists) (uses this blocklist as a source)

## Appreciation
Thanks to the following people for the help, inspiration, and support!
- [@bongochong](https://github.com/bongochong)
- [@hagezi](https://github.com/hagezi)
- [@iam-py-test](https://github.com/iam-py-test)
EOF
}

function build_list {
    blocklist_path="lists/${directory}/scams.txt"
    [[ -d "$(dirname "$blocklist_path")" ]] || mkdir "$(dirname "$blocklist_path")"  # Create directory if not present

    cat << EOF > "$blocklist_path"  # Append header onto blocklist
${3} Title: Jarelllama's Scam Blocklist
${3} Description: Blocklist for scam site domains automatically retrieved from Google Search and public databases updated daily.
${3} Homepage: https://github.com/jarelllama/Scam-Blocklist
${3} License: GNU GPLv3 (https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md)
${3} Last modified: $(date -u)
${3} Syntax: ${1}
${3} Total number of entries: $(wc -l < "$raw_file")
${3}
EOF

    [[ "$syntax" == 'Unbound' ]] && printf "server:\n" >> "$blocklist_path"  # Special case for Unbound format
    printf "%s\n" "$(awk -v before="$4" -v after="$5" '{print before $0 after}' "$raw_file")" \
        >> "$blocklist_path"  # Append formatted domains onto blocklist
}

function print_stats {
    [[ -n "$1" ]] && source="$1" || source="All sources" 
    printf "%5s |%10s |%8s%% | %s\n" "$(count "$today" "$1")" "$(count "$yesterday" "$1")" "$(count "excluded" "$1" )" "$source"
}

function count {
    scope="$1"
    source="$2"
    # Count % of excluded domains of raw count retrieved from each source
    if [[ "$scope" == 'excluded' ]]; then
        raw_count=$(csvgrep -c 13 -m 'yes' "$source_log" | csvgrep -c 2 -m "$source" | csvcut -c 4 | awk '{total += $1} END {print total}')
        if [[ "$raw_count" -eq 0 ]]; then
            printf "0" && return
        fi
        white_count=$(csvgrep -c 13 -m 'yes' "$source_log" | csvgrep -c 2 -m "$source" | csvcut -c 6 | awk '{total += $1} END {print total}')
        dead_count=$(csvgrep -c 13 -m 'yes' "$source_log" | csvgrep -c 2 -m "$source" | csvcut -c 7 | awk '{total += $1} END {print total}')
        redundant_count=$(csvgrep -c 13 -m 'yes' "$source_log" | csvgrep -c 2 -m "$source" | csvcut -c 8 | awk '{total += $1} END {print total}')
        excluded_count=$((white_count + dead_count + redundant_count))
        printf "%s" "$((excluded_count*100/raw_count))"  # Print % excluded
        return
    # Count number of Google Search queries made
    elif [[ "$scope" == 'queries' ]]; then
        queries=$(csvgrep -c 1 -m "$today" "$source_log" | csvgrep -c 2 -m 'Google Search' | csvcut -c 11 | awk '{total += $1} END {print total}')
        [[ "$queries" -lt 100 ]] && printf "%s" "$queries" || printf "%s (rate limited)" "$queries"
        return
    fi
    # Print dash if no runs for that day found
    if ! grep -qF "$scope" "$source_log"; then
        printf "-" && return
    fi
    # Sum up all domains retrieved by that source for that day
    csvgrep -c 1 -m "$scope" "$source_log" | csvgrep -c 13 -m 'yes' | csvgrep -c 2 -m "$source" | csvcut -c 5 | awk '{total += $1} END {print total}'
}

function format_list {
    bash data/tools.sh "format" "$1"
}

function build_adblock {
    syntax='Adblock Plus'
    directory="adblock"
    comment='!'
    before='||'
    after='^'
    build_list "$syntax" "$directory" "$comment" "$before" "$after"
}

function build_dnsmasq {
    syntax='Dnsmasq'
    directory="dnsmasq"
    comment='#'
    before='local=/'
    after='/'
    build_list "$syntax" "$directory" "$comment" "$before" "$after"
}

function build_unbound {
    syntax='Unbound'
    directory="unbound"
    comment='#'
    before='local-zone: "'
    after='." always_nxdomain'
    build_list "$syntax" "$directory" "$comment" "$before" "$after"
}

function build_wildcard_asterisk {
    syntax='Wildcard Asterisk'
    directory="wildcard_asterisk"
    comment='#'
    before='*.'
    after=''
    build_list "$syntax" "$directory" "$comment" "$before" "$after"
}

function build_wildcard_domains {
    syntax='Wildcard Domains'
    directory="wildcard_domains"
    comment='#'
    before=''
    after=''
    build_list "$syntax" "$directory" "$comment" "$before" "$after"
}

main

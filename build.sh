#!/bin/bash
raw_file='data/raw.txt'
raw_light_file='data/raw_light.txt'
search_terms_file='config/search_terms.csv'
source_log='config/source_log.csv'
today=$(date -u +"%d-%m-%y")
yesterday=$(date -ud "yesterday" +"%d-%m-%y")

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
Blocklist for scam site domains automatically retrieved daily from Google Search and public databases. Automated retrieval is done daily at 00:00 UTC.
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
[![Run tests](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/test.yml/badge.svg)](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/test.yml)
[![End-to-end build](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/e2e.yml/badge.svg)](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/e2e.yml)
\`\`\`
Total domains: $(wc -l < "$raw_file")

Statistics for each source:
Today | Yesterday | Excluded | Source
$(print_stats "Google Search")
$(print_stats "aa419.org")
$(print_stats "dfpi.ca.gov")
$(print_stats "guntab.com")
$(print_stats "petscams.com")
$(print_stats "scam.directory")
$(print_stats "scamadviser.com")
$(print_stats "stopgunscams.com")
$(print_stats "Manual") Entries
$(print_stats)

*The Excluded % is of domains not included in the
 blocklist. Mostly dead and whitelisted domains.
*Only active sources are shown. See the full list of
 sources in SOURCES.md.
\`\`\`
All data retrieved are publicly available and can be viewed from their respective [sources](https://github.com/jarelllama/Scam-Blocklist/blob/main/SOURCES.md).

## Light version
Targeted at list maintainers, a light version of the blocklist is available in the [lists](https://github.com/jarelllama/Scam-Blocklist/tree/main/lists) directory.

<details>
<summary>Details about the light version</summary>
<ul>
<li>Intended for collated blocklists cautious about size</li>
<li>Does not use sources whose domains cannot be filtered by date added</li>
<li>Only retrieves domains added in the last month by their respective sources (this is not the same as the domain registration date), whereas the full blocklist includes domains added from 2 months back and onwards</li>
<li>Parked domains are removed from the list. This is currently only being done for the light version due to the processing time required</li>
<li>! Dead domains that become alive again are not added back to the blocklist (due to limitations in the way the dead domains are recorded)</li>
</ul>
Sources excluded from the light version are marked in SOURCES.md.
<br>
<br>
Total domains: $(wc -l < "$raw_light_file")
</details>

## Retrieving scam domains from Google Search
Google provides a [Search API](https://developers.google.com/custom-search/v1/introduction) to retrieve JSON-formatted results from Google Search. The script uses a list of search terms almost exclusively used in scam sites to retrieve domains. See the list of search terms here: [search_terms.csv](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/search_terms.csv)

#### Rationale
Scam sites often do not have a long lifespan; malicious domains may be replaced before they can be manually reported. By programmatically searching Google using paragraphs from real-world scam sites, new domains can be added as soon as Google crawls the site. This requires no manual reporting.

The list of search terms is proactively updated and is mostly sourced from investigating new scam site templates seen on [r/Scams](https://www.reddit.com/r/Scams/).

#### Limitations
The Google Custom Search JSON API only provides 100 daily free search queries per API key (which is why this project uses two API keys).

To optimize the number of search queries made, each search term is frequently benchmarked on its number of new domains and false positives. Underperforming search terms are flagged and disabled. The figures for each search term can be viewed here: [source_log.csv](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/source_log.csv)

#### Statistics
\`\`\`
Active search terms: $(count "active_search_terms")
Queries made today: $(count "queries")
Domains retrieved today: $(count "$today" "Google Search")
\`\`\`

#### Regarding other sources
The full domain retrieval process for all sources can be viewed in the repository's code.

## Filtering process
- The domains collated from all sources are filtered against a whitelist (scam reporting sites, forums, vetted stores, etc.)
- The domains are checked against the [Tranco Top Sites Ranking](https://tranco-list.eu/) for potential false positives which are then vetted manually
- Common subdomains like 'www.' are removed to make use of wildcard matching for all other subdomains. See the list of checked subdomains here: [subdomains.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/subdomains.txt)
- Redundant entries are removed via wildcard matching. For example, 'sub.spam.com' is a wildcard match of 'spam.com' and is, therefore, redundant and is removed. Many of these wildcard domains also happen to be malicious hosting sites
- Only domains are included in the blocklist; IP addresses are checked for resolving DNS records and URLs are stripped down to their domains

The full filtering process can be viewed in the repository's code.

## Dead domains
Dead domains are removed daily using [AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter). Note that domains acting as wildcards are excluded from this process.

Dead domains that are resolving again are included back into the blocklist.

## Why the Hosts format is not supported
Malicious domains often have [wildcard DNS records](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/) that allow scammers to create large amounts of subdomain records, such as 'random-subdomain.scam.com'. Each subdomain can point to a separate scam site and collating them all would inflate the blocklist size. Therefore, only formats supporting wildcard matching are built.

## Sources
Moved to [SOURCES.md](https://github.com/jarelllama/Scam-Blocklist/blob/main/SOURCES.md).

## Resources
- [AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter): tool for checking Adblock rules for dead domains
- [Legality of web scraping](https://www.quinnemanuel.com/the-firm/publications/the-legal-landscape-of-web-scraping/): the law firm of Quinn Emanuel Urquhart & Sullivan's memoranda on web scraping
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
    [[ -z "$comment" ]] && comment='#'  # Set default comment to '#'

    # Loop through the two blocklist versions
    for i in {1..2}; do
        [[ "$i" -eq 1 ]] && { list_name='scams.txt'; version=''; source_file="$raw_file"; }
        [[ "$i" -eq 2 ]] && { list_name='scams_light.txt'; version='LIGHT VERSION'; source_file="$raw_light_file"; }
        blocklist_path="lists/${directory}/${list_name}"
        [[ ! -d "$(dirname "$blocklist_path")" ]] && mkdir "$(dirname "$blocklist_path")"  # Create directory if not present

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

function print_stats {
    [[ -n "$1" ]] && source="$1" || source="All sources"
    printf "%5s |%10s |%8s%% | %s\n" "$(count "$today" "$1")" "$(count "$yesterday" "$1")" "$(count "excluded" "$1" )" "$source"
}

function count {
    scope="$1"
    source="$2"

    # Count % of excluded domains of raw count retrieved from each source
    if [[ "$scope" == 'excluded' ]]; then
        csvgrep -c 2 -m "$source" "$source_log" | csvgrep -c 13 -m 'yes' > source_rows.tmp
        raw_count=$(csvcut -c 4 source_rows.tmp | awk '{total += $1} END {print total}')
        [[ "$raw_count" -eq 0 ]] && { printf "0"; return; }  # Return if raw count is 0 to avoid divide by zero error
        white_count=$(csvcut -c 6 source_rows.tmp | awk '{total += $1} END {print total}')
        dead_count=$(csvcut -c 7 source_rows.tmp | awk '{total += $1} END {print total}')
        redundant_count=$(csvcut -c 8 source_rows.tmp | awk '{total += $1} END {print total}')
        parked_count=$(csvcut -c 9 source_rows.tmp | awk '{total += $1} END {print total}')
        excluded_count=$((white_count + dead_count + redundant_count + parked_count))
        printf "%s" "$((excluded_count*100/raw_count))"  # Print % excluded
        rm source_rows.tmp
        return

    # Count number of Google Search queries made
    elif [[ "$scope" == 'queries' ]]; then
        queries=$(csvgrep -c 1 -m "$today" "$source_log" | csvgrep -c 2 -m 'Google Search' | csvcut -c 12 | awk '{total += $1} END {print total}')
        [[ "$queries" -lt 205 ]] && printf "%s" "$queries" || printf "%s (rate limited)" "$queries"
        return

    # Count number of active search terms
    elif [[ "$scope" == 'active_search_terms' ]]; then
        csvgrep -c 2 -m 'y' -i "$search_terms_file" | tail -n +2 | wc -l
        return
    fi

    # Sum up all domains retrieved by that source for that day
    ! grep -qF "$scope" "$source_log" && { printf "-"; return; }  # Print dash if no runs for that day found
    csvgrep -c 1 -m "$scope" "$source_log" | csvgrep -c 13 -m 'yes' | csvgrep -c 2 -m "$source" | csvcut -c 5 | awk '{total += $1} END {print total}'
}

function format_list {
    bash data/tools.sh "format" "$1"
}

function build_adblock {
    syntax='Adblock Plus' && directory='adblock' && comment='!' && before='||' && after='^'
    build_list
}

function build_dnsmasq {
    syntax='Dnsmasq' && directory='dnsmasq' && before='local=/' && after='/'
    build_list
}

function build_unbound {
    syntax='Unbound' && directory='unbound' && before='local-zone: "' && after='." always_nxdomain'
    build_list
}

function build_wildcard_asterisk {
    syntax='Wildcard Asterisk' && directory='wildcard_asterisk' && before='*.' && after=''
    build_list
}

function build_wildcard_domains {
    syntax='Wildcard Domains' && directory='wildcard_domains' && before='' && after=''
    build_list
}

main

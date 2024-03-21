#!/bin/bash
raw_file='data/raw.txt'
source_log='data/source_log.csv'
today="$(date -u +"%d-%m-%y")"
yesterday="$(date -ud "yesterday" +"%d-%m-%y")"

function main {
    command -v csvstat &> /dev/null || pip install -q csvkit
    for file in config/* data/* data/processing/*; do  # Format files in the config and data directory
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

Blocklist for scam sites retrieved from Google Search and public databases, automatically updated daily at 17:00 UTC.

| Format | Syntax |
| --- | --- |
| [Adblock Plus](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/adblock/scams.txt) | \|\|scam.com^ |
| [Dnsmasq](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/dnsmasq/scams.txt) | local=/scam.com/ |
| [Unbound](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/unbound/scams.txt) | local-zone: "scam.com." always_nxdomain |
| [Wildcard Asterisk](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_asterisk/scams.txt) | \*.scam.com |
| [Wildcard Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_domains/scams.txt) | scam.com |

## Stats

\`\`\`
Total domains: $(wc -w < "$raw_file")

Total | Today | Yesterday | Source *
$(print_stats "Google Search" "Google Search")
$(print_stats "aa419.org" "aa419.org")
$(print_stats "guntab.com" "guntab.com")
$(print_stats "petscams.com" "petscams.com")
$(print_stats "scam.delivery" "scam.delivery")
$(print_stats "scam.directory" "scam.directory")
$(print_stats "scamadviser.com" "scamadviser.com")
$(print_stats "stopgunscams.com" "stopgunscams.com")
$(printf "%5s" "$(wc -w < "$raw_file")") |$(printf "%6s" "$(count "$today" "")") |$(printf "%10s" "$(count "$yesterday" "")") | All sources

*Domains added manually are excluded from the daily figures.
\`\`\`

All data retrieved are publicly available and can be viewed in their respective [sources](https://github.com/jarelllama/Scam-Blocklist/#Sources).

## Retrieving scam domains from Google Search

Google provides a [Search API](https://developers.google.com/custom-search/v1/introduction) to retrieve JSON-formatted results from Google Search. The script uses a list of search terms almost exclusively used in scam sites to retrieve domains. These search terms are manually added while investigating scam sites. See the list of search terms here: [search_terms.csv](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/search_terms.csv)

#### Rationale

Scam sites often do not have a long lifespan; malicious domains may be replaced before they can be manually reported. By programmatically searching Google using paragraphs from real-world scam sites, new domains can be added as soon as Google crawls the site. This requires no manual reporting.

The list of search terms is proactively updated and is mostly retrieved from new scam site templates seen on r/Scams.

#### Limitations

The Google Custom Search JSON API only provides 100 free search queries per day. Because of the number of search terms used, the Google Search source can only be employed once a day.

To optimise the number of search queries made, each search term is frequently benchmarked on their numbers for new domains and false positives. The figures for each search term can be viewed here: [source_log.csv](https://github.com/jarelllama/Scam-Blocklist/blob/main/data/source_log.csv)

> Queries made today: $(csvgrep -c 1 -m "$today" | csvgrep -c 2 -m 'Google Search' "$source_log" | csvcut -c 11 | awk '{total += $1} END {print total}')

#### Regarding other sources

The full domain retrieval process for all sources can be viewed in the repository's code.

## Filtering process

- The domains collated from all sources are filtered against a whitelist (scam reporting sites, forums, vetted companies, etc.), along with other filtering
- The domains are checked against the [Tranco 1M Toplist](https://tranco-list.eu/) for potential false positives and flagged domains are vetted manually
- Redundant entries are removed via wildcard matching. For example, 'sub.spam.com' is a wildcard match of 'spam.com' and is, therefore, redundant and is removed. Many of these wildcard domains also happen to be malicious hosting sites

The full filtering process can be viewed in the repository's code.

## Dead domains

Dead domains are removed daily using [AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter). Note that domains acting as wildcards are excluded from this process.

Dead domains that have become alive again are added back into the blocklist. This check for resurrected domains is also done daily.

## Why the Hosts format is not supported

Malicious domains often have [wildcard DNS records](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/) that allow scammers to create large amounts of subdomain records, such as 'long-random-subdomain.scam.com'. To collate individual subdomains would be difficult and would inflate the blocklist size. Therefore, only formats supporting wildcard matching are built.

Additionally, wildcard domains are periodically added manually to the blocklist to reduce the number of entries via wildcard matching.

## Sources

- [Google's Custom Search JSON API](https://developers.google.com/custom-search/v1/introduction): Google Search API
- [Artists Against 419](https://db.aa419.org/fakebankslist.php): fake sites database
- [GunTab](https://www.guntab.com/scam-websites): firearm scam sites database
- [PetScams.com](https://petscams.com/): pet scam sites database
- [Scam.Delivery](https://scam.delivery/): delivery scam sites database
- [ScamAdvisor](https://www.scamadviser.com/): scam sites database
- [Scam Directory](https://scam.directory/): non-delivery scam sites database
- [stop419scams.com](https://www.stop419scams.com/): forum for reporting and exposing scams
- [StopGunScams.com](https://stopgunscams.com/): firearm scam sites database
- [Tranco Toplist](https://tranco-list.eu/): list of the 1 million top ranked domains
- [r/Scams](https://www.reddit.com/r/Scams/): for manually added sites and search terms
- [r/CryptoScamBlacklist](https://www.reddit.com/r/CryptoScamBlacklist/): for manually added sites and search terms

All data retrieved from these sources are publicly available.

## Resources

- [AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter): tool for checking Adblock rules for dead domains

- [ShellCheck](https://github.com/koalaman/shellcheck): shell script static analysis tool

- [LinuxCommand's Coding Standards](https://linuxcommand.org/lc3_adv_standards.php): shell script coding standard

- [Legality of web scraping](https://www.quinnemanuel.com/the-firm/publications/the-legal-landscape-of-web-scraping/): The law firm of Quinn Emanuel Urquhart & Sullivan's memoranda on web scraping

## See also

- [Hagezi's DNS Blocklists](https://github.com/hagezi/dns-blocklists) (uses this blocklist as a source)

- [Durablenapkin's Scam Blocklist](https://github.com/durablenapkin/scamblocklist)

- [Elliotwutingfeng's Global Anti-Scam Organization Blocklist](https://github.com/elliotwutingfeng/GlobalAntiScamOrg-blocklist)

- [Elliotwutingfeng's Inversion DNSBL Blocklist](https://github.com/elliotwutingfeng/Inversion-DNSBL-Blocklists)

## Appreciation

Thanks to the following people for the help, inspiration and support!

- [@hagezi](https://github.com/hagezi)

- [@iam-py-test](https://github.com/iam-py-test)

- [@bongochong](https://github.com/bongochong)
EOF
}

function build_list {
    blocklist_path="lists/${directory}/scams.txt"
    [[ -d "$(dirname $blocklist_path)" ]] || mkdir "$(dirname $blocklist_path)"  # Create directory if not present

    cat << EOF > "$blocklist_path"  # Append header onto blocklist
${3} Title: Jarelllama's Scam Blocklist
${3} Description: Blocklist for scam sites retrieved from Google Search and public databases, automatically updated daily.
${3} Homepage: https://github.com/jarelllama/Scam-Blocklist
${3} License: GNU GPLv3 (https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md)
${3} Last modified: $(date -u)
${3} Syntax: ${1}
${3} Total number of entries: $(wc -l <<< "$raw_file")
${3}
EOF

    [[ "$syntax" == 'Unbound' ]] && printf "server:\n" >> "$blocklist_path"  # Special case for Unbound syntax
    printf "%s\n" "$(awk -v before="$4" -v after="$5" '{print before $0 after}' "$raw_file")" \
        >> "$blocklist_path"  # Append formatted domains onto blocklist
}

function print_stats {
    printf "    - |%6s |%10s | %s\n" "$(count "$today" "$1")" "$(count "$yesterday" "$1")" "$2"
}

function count {
    # Find all runs from that particular source on that specific day
    runs=$(csvgrep -c 1 -m "$1" "$source_log" | csvgrep -c 12 -m 'yes' | csvgrep -c 2 -m "$2" | csvcut -c 5 | tail +2)
    printf "%s" "$runs" | awk '{total += $1} END {print total}'  # Sum up domains retrieved from all runs of that source
}

function format_list {
    [[ -f "$1" ]] || return  # Return if file does not exist
    if [[ "$1" == *.csv ]]; then  # If file is a CSV file, do not sort
        sed -i 's/\r//; /^$/d' "$1"
        return
    elif [[ "$1" == *dead_domains_file* ]]; then  # Do not sort the dead domains file
        tr -d ' \r' < "$1" | tr -s '\n' | awk '!seen[$0]++' > "${1}.tmp" && mv "${1}.tmp" "$1"
        return
    fi
    # Remove whitespaces, carriage return characters, empty lines, sort and remove duplicates
    tr -d ' \r' < "$1" | tr -s '\n' | sort -u > "${1}.tmp" && mv "${1}.tmp" "$1"
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

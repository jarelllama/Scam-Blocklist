#!/bin/bash
raw_file='data/raw.txt'
source_log='data/source_log.csv'
domain_log='data/domain_log.csv'
today="$(TZ=Asia/Singapore date +"%d-%m-%y")"
yesterday="$(TZ=Asia/Singapore date -d "yesterday" +"%d-%m-%y")"

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
    aa419_today=$(count "$today" "aa419.org")
    aa419_yesterday=$(count "$yesterday" "aa419.org")
    guntab_today=$(count "$today" "guntab.com")
    guntab_yesterday=$(count "$yesterday" "guntab.com")
    google_today=$(count "$today" "Google Search")
    google_yesterday=$(count "$yesterday" "Google Search")
    petscams_today=$(count "$today" "petscams.com")
    petscams_yesterday=$(count "$yesterday" "petscams.com")
    stopgunscams_today=$(count "$today" "stopgunscams.com")
    stopgunscams_yesterday=$(count "$yesterday" "stopgunscams.com")
    scamdelivery_today=$(count "$today" "scam.delivery")
    scamdelivery_yesterday=$(count "$yesterday" "scam.delivery")
    scamdirectory_today=$(count "$today" "scam.directory")
    scamdirectory_yesterday=$(count "$yesterday" "scam.directory")

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
    - |$(printf "%6s" "$google_today") |$(printf "%10s" "$google_yesterday") | Google Search
    - |$(printf "%6s" "$aa419_today") |$(printf "%10s" "$aa419_yesterday") | aa419.org
    - |$(printf "%6s" "$guntab_today") |$(printf "%10s" "$guntab_yesterday") | guntab.com
    - |$(printf "%6s" "$petscams_today") |$(printf "%10s" "$petscams_yesterday") | petscams.com
    - |$(printf "%6s" "$scamdelivery_today") |$(printf "%10s" "$scamdelivery_yesterday") | scam.delivery
    - |$(printf "%6s" "$scamdirectory_today") |$(printf "%10s" "$scamdirectory_yesterday") | scam.directory
    - |$(printf "%6s" "$stopgunscams_today") |$(printf "%10s" "$stopgunscams_yesterday") | stopgunscams.com
$(printf "%5s" "$(wc -w < "$raw_file")") |$(printf "%6s" "$(count "$today" "")") |$(printf "%10s" "$(count "$yesterday" "")") | All sources

The 5 most recently added domains:
$(csvgrep -c 2 -m "new_domain" "$domain_log" | csvcut -c 3 | tail +2 | tail -5)

*Domains added manually are excluded from the daily figures.
\`\`\`

All data retrieved are publicly available and can be viewed in their respective [sources](https://github.com/jarelllama/Scam-Blocklist/#Sources).

## Retrieving scam domains from Google Search

Google provides a [Search API](https://developers.google.com/custom-search/v1/introduction) to retrieve JSON-formatted results from Google Search. The script uses a list of search terms almost exclusively used in scam sites to retrieve results, of which the domains are added to the blocklist. These search terms are manually added while investigating scam sites. See the list of search terms here: [search_terms.csv](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/search_terms.csv)

#### Why this method is effective

Scam sites often do not have a long lifespan; domains can be created and removed within the same month. By searching Google Search using paragraphs of real-world scam sites, new domains can be added as soon as Google crawls the site. The search terms are often taken from sites reported on r/Scams, where real users are encountering these sites in the wild.

#### Limitations

The Google Custom Search JSON API only provides 100 free search queries per day. Because of the number of search terms used, the Google Search source can only be employed once a day, otherwise, subsequent runs might return with 0 domains.

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

Malicious domains often have [wildcard DNS records](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/) that allow scammers to create large amounts of subdomain records, such as 'long-random-subdomain.scam.com'. To collate individual subdomains would be a difficult task and would inflate the blocklist size. Therefore, only formats supporting wildcard matching are built.

## Malicious hosting sites

Some wildcard domains are added manually to the blocklist to reduce the number of entries via wildcard matching. Many of these wildcard domains are discovered to be malicious hosting sites with multiple subdomains pointing to scam sites. These malicious hosting sites are included in the blocklist and can be found among the wildcard domains in [wildcards.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/data/wildcards.txt).

## Sources

- [Google's Custom Search JSON API](https://developers.google.com/custom-search/v1/introduction): Google Search API
- [Artists Against 419](https://db.aa419.org/fakebankslist.php): fake sites database
- [GunTab](https://www.guntab.com/scam-websites): firearm scam sites database
- [PetScams.com](https://petscams.com/): pet scam sites database
- [scam.delivery](https://scam.delivery/): delivery scam sites database
- [Scam Directory](https://scam.directory/): non-delivery scam sites database
- [stop419scams.com](https://www.stop419scams.com/): forum for reporting and exposing scams
- [StopGunScams.com](https://stopgunscams.com/): firearm scam sites database
- [Tranco Toplist](https://tranco-list.eu/): list of the 1 million top ranked domains
- [r/Scams](https://www.reddit.com/r/Scams/): for manually added sites and search terms
- [r/CryptoScamBlacklist](https://www.reddit.com/r/CryptoScamBlacklist/): for manually added sites and search terms

All data retrieved from these sources are publicly available.

## Resources

- [AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter): tool for checking AdBlock rules for dead domains

- [ShellCheck](https://github.com/koalaman/shellcheck): shell script static analysis tool

- [LinuxCommand's Coding Standards](https://linuxcommand.org/lc3_adv_standards.php): shell script coding standard

- [Legality of web scraping](https://www.quinnemanuel.com/the-firm/publications/the-legal-landscape-of-web-scraping/): Quinn Emanuel Urquhart & Sullivan law firm's memoranda on web scraping

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

    # Format domains for each syntax type
    formatted_domains=$(awk -v before="$4" -v after="$5" '{print before $0 after}' "$raw_file")

    cat << EOF > "$blocklist_path"  # Append header onto blocklist
${3} Title: Jarelllama's Scam Blocklist
${3} Description: Blocklist for scam sites retrieved from Google Search and public databases, automatically updated daily.
${3} Homepage: https://github.com/jarelllama/Scam-Blocklist
${3} License: GNU GPLv3 (https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md)
${3} Last modified: $(date -u)
${3} Syntax: ${1}
${3} Total number of entries: $(wc -l <<< "$formatted_domains")
${3}
EOF

    [[ "$syntax" == 'Unbound' ]] && printf "server:\n" >> "$blocklist_path"  # Special case for Unbound syntax
    printf "%s\n" "$formatted_domains" >> "$blocklist_path"  # Append formatted domains onto blocklist
}

function count {
    runs=$(csvgrep -c 1 -m "$1" "$source_log" | csvgrep -c 2 -m "$2" | csvgrep -c 10 -m 'yes' | csvcut -c 5 | tail +2)  # Find all runs from that particular source
    total_count=0  # Initiaize total count
    for count in $runs; do
        total_count=$((total_count + count))  # Calculate sum of domains retrieved from that source
    done
    printf "%s" "$total_count"  # Return domain count to function caller
}

function format_list {
    [[ -f "$1" ]] || return  # Return if file does not exist
    # If file is a CSV file, do not sort
    if [[ "$1" == *.csv ]]; then
        sed -i 's/\r$//' "$1"  
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

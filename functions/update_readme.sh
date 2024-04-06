#!/bin/bash

# Updates the README.md content and statistics.

readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly SEARCH_TERMS='config/search_terms.csv'
readonly SOURCE_LOG='config/source_log.csv'
TODAY="$(date -u +"%d-%m-%y")"
YESTERDAY="$(date -ud yesterday +"%d-%m-%y")"
readonly TODAY
readonly YESTERDAY

update_readme() {
    cat << EOF > README.md
# Jarelllama's Scam Blocklist

${BLOCKLIST_DESCRIPTION} Automated retrieval is done at 00:00 UTC.

This blocklist is meant to be an alternative to blocking all newly registered domains (NRDs) seeing how many, but not all, NRDs are malicious. To reach this goal, a variety of sources are integrated to aid in the detection and recording of new malicious domains within a short timespan of their registration date.

| Format | Syntax |
| --- | --- |
| [Adblock Plus](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/adblock/scams.txt) | \|\|scam.com^ |
| [Dnsmasq](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/dnsmasq/scams.txt) | local=/scam.com/ |
| [Unbound](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/unbound/scams.txt) | local-zone: "scam.com." always_nxdomain |
| [Wildcard Asterisk](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_asterisk/scams.txt) | \*.scam.com |
| [Wildcard Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_domains/scams.txt) | scam.com |

## Statistics

[![Build and deploy](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/build_deploy.yml/badge.svg)](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/build_deploy.yml)
[![Test functions](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/test_functions.yml/badge.svg)](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/test_functions.yml)

\`\`\` text
Total domains: $(wc -l < "$RAW")

Statistics for each source:
Today | Yesterday | Excluded | Source
$(print_stats 'Google Search')
$(print_stats 'aa419.org')
$(print_stats 'dnstwist')
$(print_stats 'guntab.com')
$(print_stats 'petscams.com')
$(print_stats 'scam.directory')
$(print_stats 'scamadviser.com')
$(print_stats 'stopgunscams.com')
$(print_stats 'Manual') Entries
$(print_stats)

*The Excluded % is of domains not included in the
 blocklist. Mostly dead, whitelisted, and parked domains.
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
<li>Does not use sources that have an above average false positive rate</li?>
<li>Note that dead and parked domains that become alive/unparked are not added back into the light version (due to limitations in the way these domains are recorded)</li>
</ul>
Sources excluded from the light version are marked in SOURCES.md.
<br>
<br>
Total domains: $(wc -l < "$RAW_LIGHT")
</details>

## Sources

### Retrieving scam domains using Google Search API

Google provides a [Search API](https://developers.google.com/custom-search/v1/overview) to retrieve JSON-formatted results from Google Search. A list of search terms almost exclusively found in scam sites is used by the API to retrieve domains. See the list of search terms here: [search_terms.csv](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/search_terms.csv)

#### Effectiveness

Scam sites often do not have long lifespans; malicious domains may be replaced before they can be manually reported. By programmatically searching Google using paragraphs from real-world scam sites, new domains can be added as soon as Google crawls the site. This requires no manual reporting.

The list of search terms is proactively updated and is mostly sourced from investigating new scam site templates seen on [r/Scams](https://www.reddit.com/r/Scams/).

#### Limitations

The Google Custom Search JSON API allows a limited number of search queries per day. To optimize the number of queries made, each search term is frequently benchmarked on its number of new domains and false positives. Underperforming search terms are flagged and disabled.

#### Statistics for Google Search source

\`\`\` text
Active search terms: $(csvgrep -c 2 -m 'y' -i "$SEARCH_TERMS" | tail -n +2 | wc -l)
Queries made today: $(grep -F "$TODAY" "$SOURCE_LOG" | grep -F 'Google Search' | csvcut -c 12 | awk '{sum += $1} END {print sum}')
Domains retrieved today: $(sum "$TODAY" 'Google Search')
\`\`\`

### Retrieving phishing NRDs using dnstwist

New phishing domains are created daily, and unlike other sources that rely on manual reporting, [dnstwist](https://github.com/elceef/dnstwist) can automatically detect new phishing domains within days of their registration date.

dnstwist is an open-source detection tool for common cybersquatting techniques like [Typosquatting](https://en.wikipedia.org/wiki/Typosquatting), [Doppelganger Domains](https://en.wikipedia.org/wiki/Doppelganger_domain), and [IDN Homograph Attacks](https://en.wikipedia.org/wiki/IDN_homograph_attack).

#### Effectiveness

On a daily basis, dnstwist uses a list of common phishing targets to find permutations of the targets' domains. The target list is a handpicked collection of cryptocurrency exchanges, delivery companies, etc. collated while wary of potential false positives. The list of phishing targets can be viewed here: [phishing_targets.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/phishing_targets.txt)

The generated domain permutations are appended with commonly abused top-level domains (TLDs) sourced from [Hagezi's Most Abused TLDs feed](https://github.com/hagezi/dns-blocklists#crystal_ball-most-abused-tlds---protects-against-known-malicious-top-level-domains-). The domains are then checked for matches in a newly registered domains (NRDs) feed comprising domains registered within the last 30 days. Paired with the NRD feed, dnstwist can effectively retrieve newly-created phishing domains with marginal false positives.

### Regarding other sources

All sources used presently or in the past are credited here: [SOURCES.md](https://github.com/jarelllama/Scam-Blocklist/blob/main/SOURCES.md)

The domain retrieval process for all sources can be viewed in the repository's code.

## Automated filtering process

- The domains collated from all sources are filtered against an actively maintained whitelist (scam reporting sites, forums, vetted stores, etc.)
- The domains are checked against the [Tranco Top Sites Ranking](https://tranco-list.eu/) for potential false positives which are then vetted manually
- Common subdomains like 'www' are removed to make use of wildcard matching for all other subdomains
- Redundant entries are removed via wildcard matching. For example, 'sub.spam.com' is a wildcard match of 'spam.com' and is, therefore, redundant and is removed. Many of these wildcard domains also happen to be malicious hosting sites
- Only domains are included in the blocklist; IP addresses are manually checked for resolving DNS records and URLs are stripped down to their domains
- Entries that require manual verification/intervention are sent in a Telegram notification for fast remediations

The full filtering process can be viewed in the repository's code.

## Dead domains

Dead domains are removed daily using AdGuard's [Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter). Note that domains acting as wildcards are excluded from this process.

Dead domains that are resolving again are included back into the blocklist.

## Parked domains

From initial testing, [9%](https://github.com/jarelllama/Scam-Blocklist/commit/84e682fea95866670dd99f5c98f350bc7377011a) of the blocklist consisted of [parked domains](https://www.godaddy.com/resources/ae/skills/parked-domain) that inflate the number of entries. Because these domains pose no real threat (besides the obnoxious advertising), they are removed from the blocklist daily. A list of common parked domain messages is used to detect these domains and can be viewed here: [parked_terms.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/parked_terms.txt)

If these parked sites no longer contain any of the parked messages, they are assumed to be unparked and are added back into the blocklist.

## Why the Hosts format is not supported

Malicious domains often have [wildcard DNS records](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/) that allow scammers to create large amounts of subdomain records, such as 'random-subdomain.scam.com'. Each subdomain can point to a separate scam site and collating them all would inflate the blocklist size. Therefore, only formats supporting wildcard matching are built.

## Resources

- [AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter): tool for checking Adblock rules for dead domains
- [Google's Shell Style Guide](https://google.github.io/styleguide/shellguide.html): Shell script style guide
- [Grammarly](https://grammarly.com/): spelling and grammar checker
- [Legality of web scraping](https://www.quinnemanuel.com/the-firm/publications/the-legal-landscape-of-web-scraping/): the law firm of Quinn Emanuel Urquhart & Sullivan's memoranda on web scraping
- [ShellCheck](https://github.com/koalaman/shellcheck): shell script static analysis tool
- [who.is](https://who.is/): WHOIS and DNS lookup tool

## See also

- [Durablenapkin's Scam Blocklist](https://github.com/durablenapkin/scamblocklist)
- [Elliotwutingfeng's Global Anti-Scam Organization Blocklist](https://github.com/elliotwutingfeng/GlobalAntiScamOrg-blocklist)
- [Elliotwutingfeng's Inversion DNSBL Blocklist](https://github.com/elliotwutingfeng/Inversion-DNSBL-Blocklists)
- [Hagezi's DNS Blocklists](https://github.com/hagezi/dns-blocklists) (uses this blocklist as a source)
- [oisd blocklist](https://oisd.nl/) (uses this blocklist as a source)

## Appreciation

Thanks to the following people for the help, inspiration, and support!

- [@bongochong](https://github.com/bongochong)
- [@hagezi](https://github.com/hagezi)
- [@iam-py-test](https://github.com/iam-py-test)
- [@sjhgvr](https://github.com/sjhgvr)
EOF
}

# Function 'print_stats' is an echo wrapper that returns the statistics
# for the given source.
#   $1: source to process (default is all sources)
print_stats() {
    printf "%5s |%10s |%8s%% | %s\n" \
        "$(sum "$TODAY" "$1")" "$(sum "$YESTERDAY" "$1")" "$(count_excluded "$1" )" "${1:-All sources}"
}

# Function 'sum' is an echo wrapper that returns the total sum of
# domains retrieved by the given source for that particular day.
#   $1: day to process
#   $2: source to process (default is all sources)
sum() {
    # Print dash if no runs for that day found
    ! grep -qF "$1" "$SOURCE_LOG" && { printf "-"; return; }
    grep -F "$1" "$SOURCE_LOG" | grep -F "$2" | csvgrep -c 14 -m yes \
        | csvcut -c 5 | awk '{sum += $1} END {print sum}'
}

# Function 'count_excluded' is an echo wrapper that returns the percentage
# of excluded domains out of the raw count retrieved from the given source.
#   $1: source to process (default is all sources)
count_excluded() {
    grep -F "$1" "$SOURCE_LOG" | csvgrep -c 14 -m yes > rows.tmp

    raw_count="$(csvcut -c 4 rows.tmp | awk '{sum += $1} END {print sum}')"
    # Return if raw count is 0 to avoid divide by zero error
    (( raw_count == 0 )) && { printf "0"; return; }
    white_count="$(csvcut -c 6 rows.tmp | awk '{sum += $1} END {print sum}')"
    dead_count="$(csvcut -c 7 rows.tmp | awk '{sum += $1} END {print sum}')"
    redundant_count="$(csvcut -c 8 rows.tmp | awk '{sum += $1} END {print sum}')"
    parked_count="$(csvcut -c 9 rows.tmp | awk '{sum += $1} END {print sum}')"
    excluded_count="$(( white_count + dead_count + redundant_count + parked_count ))"

    printf "%s" "$(( excluded_count * 100 / raw_count ))"
}

# Entry point

trap 'find . -maxdepth 1 -type f -name "*.tmp" -delete' EXIT

# Install csvkit
command -v csvgrep &> /dev/null || pip install -q csvkit

for file in config/* data/*; do
    bash functions/tools.sh format "$file"
done

update_readme

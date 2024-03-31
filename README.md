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
[![Build and deploy](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/build_deploy.yml/badge.svg)](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/build_deploy.yml)
[![Test functions](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/test_functions.yml/badge.svg)](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/test_functions.yml)
```
Total domains: 21034

Statistics for each source:
Today | Yesterday | Excluded | Source
    - |        33 |       3% | Google Search
    - |        15 |       9% | aa419.org
    - |         0 |      52% | dfpi.ca.gov
    - |        10 |      14% | guntab.com
    - |         2 |       7% | petscams.com
    - |         0 |      12% | scam.directory
    - |         0 |      31% | scamadviser.com
    - |         0 |       5% | stopgunscams.com
    - |         0 |       7% | Manual Entries
    - |        60 |      10% | All sources

*The Excluded % is of domains not included in the
 blocklist. Mostly dead, whitelisted and parked domains.
*Only active sources are shown. See the full list of
 sources in SOURCES.md.
```
All data retrieved are publicly available and can be viewed from their respective [sources](https://github.com/jarelllama/Scam-Blocklist/blob/main/SOURCES.md).

## Light version
Targeted at list maintainers, a light version of the blocklist is available in the [lists](https://github.com/jarelllama/Scam-Blocklist/tree/main/lists) directory.

<details>
<summary>Details about the light version</summary>
<ul>
<li>Intended for collated blocklists cautious about size</li>
<li>Does not use sources whose domains cannot be filtered by date added</li>
<li>Only retrieves domains added in the last month by their respective sources (this is not the same as the domain registration date), whereas the full blocklist includes domains added from 2 months back and onwards</li>
<li>! Dead and parked domains that become resolving/unparked are not added back to the blocklist (due to limitations in the way these domains are recorded)</li>
</ul>
Sources excluded from the light version are marked in SOURCES.md.
<br>
<br>
Total domains: 2082
</details>

## Retrieving scam domains from Google Search
Google provides a [Search API](https://developers.google.com/custom-search/v1/overview) to retrieve JSON-formatted results from Google Search. The script uses a list of search terms almost exclusively used in scam sites to retrieve domains. See the list of search terms here: [search_terms.csv](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/search_terms.csv)

#### Rationale
Scam sites often do not have a long lifespan; malicious domains may be replaced before they can be manually reported. By programmatically searching Google using paragraphs from real-world scam sites, new domains can be added as soon as Google crawls the site. This requires no manual reporting.

The list of search terms is proactively updated and is mostly sourced from investigating new scam site templates seen on [r/Scams](https://www.reddit.com/r/Scams/).

#### Limitations
The Google Custom Search JSON API only provides 100 daily free search queries per API key (which is why this project uses two API keys).

To optimize the number of search queries made, each search term is frequently benchmarked on its number of new domains and false positives. Underperforming search terms are flagged and disabled. The figures for each search term can be viewed here: [source_log.csv](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/source_log.csv)

#### Statistics for Google Search source
```
Active search terms: 14
Queries made today: 0
Domains retrieved today: -
```

#### Regarding other sources
The full domain retrieval process for all sources can be viewed in the repository's code.

## Filtering process
- The domains collated from all sources are filtered against a whitelist (scam reporting sites, forums, vetted stores, etc.)
- The domains are checked against the [Tranco Top Sites Ranking](https://tranco-list.eu/) for potential false positives which are then vetted manually
- Common subdomains like 'www' are removed to make use of wildcard matching for all other subdomains. See the list of checked subdomains here: [subdomains.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/subdomains.txt)
- Redundant entries are removed via wildcard matching. For example, 'sub.spam.com' is a wildcard match of 'spam.com' and is, therefore, redundant and is removed. Many of these wildcard domains also happen to be malicious hosting sites
- Only domains are included in the blocklist; IP addresses are manually checked for resolving DNS records and URLs are stripped down to their domains

The full filtering process can be viewed in the repository's code.

## Dead domains
Dead domains are removed daily using AdGuard's [Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter). Note that domains acting as wildcards are excluded from this process.

Dead domains that are resolving again are included back in the blocklist.

## Parked domains
From initial testing, [9%](https://github.com/jarelllama/Scam-Blocklist/commit/84e682fea95866670dd99f5c98f350bc7377011a) of the blocklist consisted of [parked domains](https://www.godaddy.com/resources/ae/skills/parked-domain) that inflate the number of entries. Because these domains pose no real threat (besides the obnoxious advertising), they are removed from the blocklist daily. A list of common parked domain messages is used to detect these domains and can be viewed here: [parked_terms.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/parked_terms.txt)

If these parked sites no longer contain any of the parked messages, they are assumed to be unparked and are added back to the blocklist.
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

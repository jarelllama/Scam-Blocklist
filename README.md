# Jarelllama's Scam Blocklist
Blocklist for scam sites automatically retrieved from Google Search and public databases, updated daily at 17:00 UTC.
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
```
Total domains: 15863

Statistics for each source*:

Today | Yesterday | Dead | Source
  126 |        20 |   0% | Google Search
    8 |        28 |  11% | aa419.org
  133 |         0 |   0% | dfpi.ca.gov
    0 |         2 |  13% | guntab.com
    0 |        32 |   8% | petscams.com
    0 |         0 |   0% | scam.delivery
 1175 |         1 |   5% | scam.directory
    0 |         3 |  20% | scamadviser.com
    0 |         9 |   6% | stopgunscams.com
 1442 |        95 |  10% | All sources

*Dead domains are counted upon retrieval and are
 not included in the blocklist.
*Domains added manually are not counted as a source.
```
All data retrieved are publicly available and can be viewed in their respective [sources](https://github.com/jarelllama/Scam-Blocklist/#Sources).

## Retrieving scam domains from Google Search
Google provides a [Search API](https://developers.google.com/custom-search/v1/introduction) to retrieve JSON-formatted results from Google Search. The script uses a list of search terms almost exclusively used in scam sites to retrieve domains. These search terms are manually added while investigating scam sites. See the list of search terms here: [search_terms.csv](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/search_terms.csv)

#### Rationale
Scam sites often do not have a long lifespan; malicious domains may be replaced before they can be manually reported. By programmatically searching Google using paragraphs from real-world scam sites, new domains can be added as soon as Google crawls the site. This requires no manual reporting.

The list of search terms is proactively updated and is mostly retrieved from new scam site templates seen on r/Scams.

#### Limitations
The Google Custom Search JSON API only provides ~100 free search queries per day. Because of the number of search terms used, the Google Search source can only be employed once a day.

To optimise the number of search queries made, each search term is frequently benchmarked on their numbers for new domains and false positives. The figures for each search term can be viewed here: [source_log.csv](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/source_log.csv)

> Queries made today: 133 (rate limited)

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
- [DFPI's Crypto Scam Tracker](https://dfpi.ca.gov/crypto-scams/): crypto scams database
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

- [who.is](https://who.is/): WHOIS and DNS lookup tool

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

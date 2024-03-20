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

```
Total domains: 16264

Total | Today | Yesterday | Source *
    - |   115 |         3 | Google Search
    - |   182 |       105 | aa419.org
    - |    62 |         5 | guntab.com
    - |    21 |      7801 | petscams.com
    - |     0 |       693 | scam.delivery
    - |     0 |      1250 | scam.directory
    - |   148 |         0 | scamadviser.com
    - |     4 |       224 | stopgunscams.com
16264 |   532 |     10081 | All sources

5 recently added domains:
roseberners.com
bravecanecorsohome.com
borisshichonkennel.com
glocksforsale.net
ashdavefrenchies.com

*Domains added manually are excluded from the daily figures.
```

All data retrieved are publicly available and can be viewed in their respective [sources](https://github.com/jarelllama/Scam-Blocklist/#Sources).

## Retrieving scam domains from Google Search

Google provides a [Search API](https://developers.google.com/custom-search/v1/introduction) to retrieve JSON-formatted results from Google Search. The script uses a list of search terms almost exclusively used in scam sites to retrieve domains. These search terms are manually added while investigating scam sites. See the list of search terms here: [search_terms.csv](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/search_terms.csv)

#### Rationale

Scam sites often do not have a long lifespan; malicious domains may be replaced before they can be manually reported. By programmatically searching Google using paragraphs from real-world scam sites, new domains can be added as soon as Google crawls the site. This requires no manual reporting.

The list of search terms is proactively updated and is mostly retrieved from new scam site templates seen on r/Scams.

#### Limitations

The Google Custom Search JSON API only provides 100 free search queries per day. Because of the number of search terms used, the Google Search source can only be employed once a day.

To optimise the number of search queries made, each search term is frequently benchmarked on their numbers for new domains and false positives.

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

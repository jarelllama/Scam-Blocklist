# Jarelllama's Scam Blocklist

Blocklist for newly created scam site domains automatically retrieved daily using Google Search API, automated detection, and other public sources. Automated retrieval is done at 00:00 UTC.

This blocklist is meant to be an alternative to blocking all newly registered domains (NRD) seeing how many, but not all, NRDs are malicious.

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

``` text
Total domains: 33603

Statistics for each source:
Today | Yesterday | Excluded | Source
   19 |        58 |       4% | Google Search
   20 |         1 |      11% | aa419.org
   36 |       133 |       7% | dnstwist
   24 |         8 |      17% | guntab.com
 4665 |         0 |       0% | openSquat
   15 |        19 |      10% | petscams.com
   86 |         0 |      40% | scam.directory
    3 |         3 |      39% | scamadviser.com
    9 |         2 |       5% | stopgunscams.com
    0 |         3 |       2% | Manual Entries
 4877 |       227 |      13% | All sources

*The Excluded % is of domains not included in the
 blocklist. Mostly dead, whitelisted, and parked domains.
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
<li>Does not use sources that have an above average false positive rate</li?>
<li>Note that dead and parked domains that become alive/unparked are not added back into the blocklist (due to limitations in the way these domains are recorded)</li>
</ul>
Sources excluded from the light version are marked in SOURCES.md.
<br>
<br>
Total domains: 2175
</details>

## Sources

### Retrieving scam domains using Google Search API

Google provides a [Search API](https://developers.google.com/custom-search/v1/overview) to retrieve JSON-formatted results from Google Search. A list of search terms almost exclusively used in scam sites is passed to the API to retrieve domains. See the list of search terms here: [search_terms.csv](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/search_terms.csv)

#### Effectiveness

Scam sites often do not have long lifespans; malicious domains may be replaced before they can be manually reported. By programmatically searching Google using paragraphs from real-world scam sites, new domains can be added as soon as Google crawls the site. This requires no manual reporting.

The list of search terms is proactively updated and is mostly sourced from investigating new scam site templates seen on [r/Scams](https://www.reddit.com/r/Scams/).

#### Limitations

The Google Custom Search JSON API allows a limited number of search queries per day. To optimize the number of queries made, each search term is frequently benchmarked on its number of new domains and false positives. Underperforming search terms are flagged and disabled.

#### Statistics for Google Search source

``` text
Active search terms: 16
Queries made today: 93
Domains retrieved today: 19
```

### Retrieving malicious NRDs using automated detection

New phishing domains are created daily, and unlike other sources that depend on manual reporting, [openSquat](https://github.com/atenreiro/opensquat) and [dnstwist](https://github.com/elceef/dnstwist) can effectively retrieve new phishing domains within days of their registration date.

openSquat and dnstwist are open-source tools for detecting common cybersquatting techniques like [Typosquatting](https://en.wikipedia.org/wiki/Typosquatting), [Doppelganger Domains](https://en.wikipedia.org/wiki/Doppelganger_domain), and [IDN Homograph Attacks](https://en.wikipedia.org/wiki/IDN_homograph_attack). By feeding these tools an actively updated newly registered domains (NRD) feed, they can programmatically retrieve new phishing domains with marginal false positives.

#### Process

For input, openSquat uses keywords while dnstwist uses domains for their respective detection algorithms which generate domain permutations of the input keywords/domains. Both inputs are a carefully handpicked set of common phishing targets such as cryptocurrency exchanges, delivery companies, etc. collated while wary of potential false positives.

The input datasets can be viewed here:

- [opensquat_keywords.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/opensquat_keywords.txt)
- [dnstwist_targets.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/dnstwist_targets.txt)

The generated permutations are checked for matches in an NRD feed comprising domains registered within the last 10 days for openSquat, and 30 days for dnstwist. Matched domains are collated into the blocklist after filtering.

#### Limitations

As the retrieval process requires no manual intervention, false positives may slip through despite the intensive effort put into testing the sets of input. This is a concern particularly for openSquat because of its use of keywords to feed its detection algorithm.

For this reason, the openSquat source is excluded from the light version of the blocklist. Regardless, great care is taken to reduce false positives via these actions:

- Frequent monitoring of the retrieved domains from openSquat and auditing of the list of keywords
- Automated detection and Telegram notifications for potential false positives
- Active maintenance of a whitelist that uses keyword matching which can be viewed here: [whitelist.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/whitelist.txt)

### Regarding other sources

All sources used presently or in the past are credited here: [SOURCES.md](https://github.com/jarelllama/Scam-Blocklist/blob/main/SOURCES.md)

The domain retrieval process for all sources can be viewed in the repository's code.

## Filtering process

- The domains collated from all sources are filtered against a whitelist (scam reporting sites, forums, vetted stores, etc.)
- The domains are checked against the [Tranco Top Sites Ranking](https://tranco-list.eu/) for potential false positives which are then vetted manually
- Common subdomains like 'www' are removed to make use of wildcard matching for all other subdomains
- Redundant entries are removed via wildcard matching. For example, 'sub.spam.com' is a wildcard match of 'spam.com' and is, therefore, redundant and is removed. Many of these wildcard domains also happen to be malicious hosting sites
- Only domains are included in the blocklist; IP addresses are manually checked for resolving DNS records and URLs are stripped down to their domains

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

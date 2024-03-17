# Jarelllama's Scam Blocklist

Blocklist for scam sites retrieved from Google Search and the Artists Against 419 Fake Site Database [(aa419)](https://db.aa419.org/fakebankslist.php), automatically updated daily.

| Format | Syntax |
| --- | --- |
| [Adblock Plus](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/adblock/scams.txt) | \|\|scam.com^ |
| [Dnsmasq](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/dnsmasq/scams.txt) | local=/scam.com/ |
| [Unbound](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/unbound/scams.txt) | local-zone: "scam.com." always_nxdomain |
| [Wildcard Asterisk](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_asterisk/scams.txt) | \*.scam.com |
| [Wildcard Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_domains/scams.txt) | scam.com |

## Stats

```
Total domains: 6928
Domains from Google Search: 3615
Domains from aa419: 4264

Domains found today: 5303
Domains found yesterday: 2576

The 5 most recently added domains:
www.zupapasports.com
xpresschems.com
xujia.tradefx110.com
zedexforex.com
zystfree-heaven.com
```

## How domains are added to the blocklist

### Source #1: Artists Against 419 (aa419)
- aa419 provides a database of fake sites which are scraped and cumulated into the blocklist
- Only active domains from 2022 onwards are retrieved to keep the list size small. The database can be viewed here: [db.aa419.org](https://db.aa419.org/fakebankslist.php)

### Source #2: Google Search
- The script searches Google with a list of search terms almost exclusively used in scam sites. These search terms are manually added while investigating sites on r/Scams. See the list of search terms here: [search_terms.csv](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/search_terms.csv)

### Filtering
- The domains collated from all sources are filtered against a whitelist (scam reporting sites, forums, vetted companies, etc.), along with other filtering
- The domains are checked against the [Tranco 1M Toplist](https://tranco-list.eu/) and flagged domains are vetted manually
- Redundant entries are removed via wildcard matching. For example, 'sub.spam.com' is a wildcard match of 'spam.com' and is, therefore, redundant and is removed. Many of these wildcard domains also happen to be malicious hosting sites

The full domain retrieval and filtering process can be viewed in the repository's code.

The domain retrieval process runs daily at 17:00 UTC.

## Why the Hosts format is not supported

Malicious domains often have [wildcard DNS records](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/) that allow scammers to create large amounts of subdomain records. These subdomains are often random strings such as 'longrandomstring.scam.com'. To collate individual subdomains would be a difficult task and would inflate the blocklist size. Therefore, only formats supporting wildcard matching are built.

## Malicious hosting sites

Wildcard domains are added manually to the blocklist to reduce the number of entries via wildcard matching. Many of these wildcard domains are discovered to be malicious hosting sites with multiple subdomains pointing to scam sites. These malicious hosting sites are included in the blocklist and can be found among the wildcard domains in [wildcards.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/data/wildcards.txt).

## Dead domains

Dead domains are removed daily using [AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter). Note that domains acting as wildcards are excluded from this process.

## Resources

[Artists Against 419](https://db.aa419.org/fakebankslist.php): fake site database

[Google's Custom Search JSON API](https://developers.google.com/custom-search/v1/introduction): Google Search API

[Tranco Toplist](https://tranco-list.eu/): list of the 1 million top ranked domains

[AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter): tool for checking AdBlock rules for dead domains

[ShellCheck](https://github.com/koalaman/shellcheck): shell script static analysis tool

[LinuxCommand's Coding Standards](https://linuxcommand.org/lc3_adv_standards.php): shell script coding standard

[r/Scams](https://www.reddit.com/r/Scams/)

[r/CryptoScamBlacklist](https://www.reddit.com/r/CryptoScamBlacklist/)

## See also

[Hagezi's DNS Blocklists](https://github.com/hagezi/dns-blocklists) (uses this blocklist as a source)

[Durablenapkin's Scam Blocklist](https://github.com/durablenapkin/scamblocklist)

[Elliotwutingfeng's Global Anti-Scam Organization Blocklist](https://github.com/elliotwutingfeng/GlobalAntiScamOrg-blocklist)

[Elliotwutingfeng's Inversion DNSBL Blocklist](https://github.com/elliotwutingfeng/Inversion-DNSBL-Blocklists)

[r/Scams Subreddit](https://www.reddit.com/r/Scams)

## Appreciation

Thanks to the following people for the help, inspiration and support!

[@hagezi](https://github.com/hagezi)

[@iam-py-test](https://github.com/iam-py-test)

[@bongochong](https://github.com/bongochong)

# Jarelllama's Scam Blocklist

Blocklist for scam sites automatically retrieved from Google Search, updated daily.

| Format | Syntax |
| --- | --- |
| [Adblock Plus](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/adblock/scams.txt) | \|\|scam.com^ |
| [Dnsmasq](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/dnsmasq/scams.txt) | local=/scam.com/ |
| [Unbound](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/unbound/scams.txt) | local-zone: "scam.com." always_nxdomain |
| [Wildcard Asterisk](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_asterisk/scams.txt) | \*.scam.com |
| [Wildcard Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_domains/scams.txt) | scam.com |

## Stats

```
Total domains: 3133

Domains found today: 2
Domains found yesterday: 0

The 5 most recently added domains:
yztassel.com
zirdecor.com
zivyastore.com
y2k-wave.com
amaqeng.com
```

## How domains are added to the blocklist

- The domain retrieval process searches Google with a list of search terms almost exclusively used in scam sites. These search terms are manually added by me while investigating sites on r/Scams. See the list of search terms here: [search_terms.csv](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/search_terms.csv)
- The domains from the search results are filtered against a whitelist (scam reporting sites, forums, vetted companies, etc.), along with other filtering
- Domains are checked against the [Tranco 1M Toplist](https://tranco-list.eu/) and flagged domains are vetted manually
- Redundant entries are removed via wildcard matching. For example, 'sub.spam.com' is a wildcard match of 'spam.com' and is, therefore, redundant and is removed

The full domain retrieval and filtering process can be viewed in the repository's code.

The domain retrieval process is scheduled to run daily at 16:30 UTC.

## Why the Hosts format is not supported

Malicious domains often have [wildcard DNS records](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/) that allow scammers to create large amounts of subdomain records. These subdomains are often random strings such as `longrandomstring.scam.com`. To find and collate individual subdomains would require much effort and would inflate the blocklist size. Therefore, only formats supporting wildcard matching are built.

## Dead domains

Domains with no A records are considered dead and are removed. This check is done on a weekly basis.

## See also

[Hagezi's DNS Blocklists](https://github.com/hagezi/dns-blocklists) (uses this blocklist as a source)

[Durablenapkin's Scam Blocklist](https://github.com/durablenapkin/scamblocklist)

[Elliotwutingfeng's Global Anti-Scam Organization Blocklist](https://github.com/elliotwutingfeng/GlobalAntiScamOrg-blocklist)

[Elliotwutingfeng's Inversion DNSBL Blocklist](https://github.com/elliotwutingfeng/Inversion-DNSBL-Blocklists)

[r/Scams Subreddit](https://www.reddit.com/r/Scams)

## Resources

[ShellCheck](https://www.shellcheck.net/): shell script checker

[LinuxCommand's Coding Standards](https://linuxcommand.org/lc3_adv_standards.php): shell script coding standard

[Hagezi's DNS Blocklist](https://github.com/hagezi/dns-blocklists): inspiration and reference

[Google's Custom Search JSON API](https://developers.google.com/custom-search/v1/introduction): Google Search API

## Appreciation

Thanks to the following people for the help, inspiration and support!

[@hagezi](https://github.com/hagezi)

[@iam-py-test](https://github.com/iam-py-test)

[@bongochong](https://github.com/bongochong)

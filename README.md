# Scam Blocklist

| Syntax | Entries |
| --- |:---:|
| [Adblock Plus](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/adblock.txt) | 3159 |
| [Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/domains.txt) | 6598 |

### Stats

```
Unique scam sites found:
Today: 236
Yesterday: 45
Total: 3167 (since Apr 12 2023)

Updated: Tue May 02 15:53 UTC
```

### How domains are added to the blocklist

- The script searches Google with a list of search terms almost exclusively used in scam sites. See the list of search terms here: [search_terms.txt](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/search_terms.txt)
- Domains are filtered against a whitelist (scam reporting sites, forums, genuine stores, etc.), along with other filtering
- Domains found in the Cisco Umbrella 1M toplist are checked manually
- Domains found in toplist/whitelist updates are vetted manually

Malicious domains found in [r/Scams](https://www.reddit.com/r/Scams) are occasionally added after being manually vetted.

Domains are retrieved from multiple regions such as Asia, Europe, and North America.

To see the full filtering and retrieval process check out the code in the repository.

### Subdomains

Common subdomains are added to domains with no [wildcard record](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/). See the list of subdomains checked here: [subdomains.txt](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/data/subdomains.txt)

Only the `www` and `m` subdomains are added to domains with wildcard records so as to not inflate the blocklist size.

Subdomains found in Hagezi's [merged toplist](https://github.com/hagezi/dns-data-collection/tree/main/top) are also added (thank you Hagezi).

All subdomains are only added if they are resolving (in the case of domains with wildcard records, all subdomains resolve).

### Dead domains

Domains returning `NXDOMAIN` are removed during the domain retrieval process and once a day for the full blocklist. Dead domains that resolve again are added back.

### Inspiration

After browsing r/Scams for weeks and manually reporting scam sites to Hagezi's issue tracker, I realized most scam sites follow a similar template.

There is no way I can keep up with the number of scam sites created daily but with this project, I aim to retrieve as many newly created scam sites as possible.

### See also

[Durablenapkin's Scam Blocklist](https://github.com/durablenapkin/scamblocklist)

[Hagezi's Fake list](https://github.com/hagezi/dns-blocklists#fake) (Contains both my list and Durablenapkin's list)

[Elliotwutingfeng's Global Anti Scam Organization blocklist](https://github.com/elliotwutingfeng/GlobalAntiScamOrg-blocklist)

[Reddit's r/Scams subreddit](https://www.reddit.com/r/Scams)

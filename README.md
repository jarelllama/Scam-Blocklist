# Scam Blocklist

[![Build lists](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/build_lists.yml/badge.svg)](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/build_lists.yml)

| Format | Syntax |
| --- | --- |
| [Adblock Plus](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/adblock.txt) | \|\|scam.com^ |
| [Dnsmasq](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/dnsmasq.txt) | address=/scam.com/# |
| [Unbound](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/unbound.txt) | local-zone: "scam.com." always_nxdomain |
| [Wildcard Asterisk](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_asterisk.txt) | \*.scam.com |
| [Wildcard Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_domains.txt)<br/>(no subdomains) | scam.com |

### Stats

```
ALIVE SCAM SITES: 3933
TOTAL SCAM SITES: 3937

Scam sites found:
Today: 11
Yesterday: 157
Manually: 3845
Automatically: 92

Updated: Mon May 15 03:19 UTC
```

### How domains are added to the blocklist

- The retrieval script searches Google with a list of search terms almost exclusively used in scam sites. See the list of search terms here: [search_terms.txt](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/search_terms.txt)
- Domains are filtered against a whitelist (scam reporting sites, forums, genuine stores, etc.), along with other filtering
- Domains found in the Cisco Umbrella 1M toplist are checked manually (checked during retrieval and toplist updates)

To see the full filtering and retrieval process check out the code in the repository.

Malicious domains found in [r/Scams](https://www.reddit.com/r/Scams) are occasionally added after being manually vetted.

Domains are retrieved from multiple regions such as Asia, Europe, and North America.

### Why the Domains and Host formats are not supported

Malicious domains often have [wildcard DNS records](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/) that allow for scammers to create large amounts of subdomains. Often, these subdomains are random strings such as `kwsjla.scam.com`. To block every subdomain would be a waste of effort and would inflate the blocklist substantially.

Only formats that make use of wildcard matching are supported as they block all subdomains. This allows for further optimisations that are explained below.

### Optimisations

The list building process makes use of wildcard blocking in two ways:

1. Removal of redundant entries: If the blocklist contains `spam.com`, via wildcard matching, `sub.spam.com` would be blocked as well and is, therefore, redundant and will be removed.

2. Finding common second-level domains: If `abc.spam.com` and `def.spam.com` are both present in the blocklist, they are replaced with `spam.com` to block all subdomains instead of having separate entries for each subdomain. A whitelist is used to prevent blocking genuine e-commerce/hosting domains such as `myshopify.com`.

### Dead domains

Domains returning `NXDOMAIN` are removed during the domain retrieval process and once a day for the full blocklist. Dead domains that resolve again are added back.

### Inspiration

After browsing r/Scams for weeks and manually reporting scam sites to Hagezi's issue tracker, I realized most scam sites follow a similar template.

Although I could never keep up with the number of scam sites created daily, I aim to retrieve as many new scam sites as possible with this project.

### Limitations

Most of the domains retrieved are from manually running the script on my phone's terminal emulator. After successive manual runs, I have to change VPN servers to overcome Google's IP blocking.

The number of domains retrieved in a day varies depending on my interest and free time. However, if left unattended, the blocklist is still capable of automatic daily updates but at a much lower retrieval count than if I were to manually run the script.

See [stats](https://github.com/jarelllama/Scam-Blocklist#stats) for the number of unique domains retrieved from manual and automatic runs.

### See also

[Durablenapkin's Scam Blocklist](https://github.com/durablenapkin/scamblocklist)

[Hagezi's Fake list](https://github.com/hagezi/dns-blocklists#fake) (uses my list as a source)

[Elliotwutingfeng's Global Anti Scam Organization blocklist](https://github.com/elliotwutingfeng/GlobalAntiScamOrg-blocklist)

[Reddit's r/Scams subreddit](https://www.reddit.com/r/Scams)

# Scam Blocklist

[![Build lists](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/build.yml/badge.svg)](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/build.yml)

| Format | Syntax |
| --- | --- |
| [Adblock Plus](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/adblock/scams.txt) | \|\|scam.com^ |
| [Dnsmasq](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/dnsmasq/scams.txt) | address=/scam.com/# |
| [Unbound](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/unbound/scams.txt) | local-zone: "scam.com." always_nxdomain |
| [Wildcard Asterisk](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_asterisk/scams.txt) | \*.scam.com |
| [Wildcard Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_domains/scams.txt) | scam.com |

## Stats

```
ALIVE SCAM SITES: 3952
TOTAL SCAM SITES: 4181

Scam sites found:
Today: -4
Yesterday: -2

Updated: Mon Jul 10 20:43 UTC
```

## Other blocklists

### Malicious Hosters

Blocklist for domains commonly used to host scam/malicious sites.

This list is a byproduct of the blocklist [optimisation](https://github.com/jarelllama/Scam-Blocklist/edit/main/data/README.md#optimisations) process.

| Format | Entries |
| --- |:---:|
| [Wildcard Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_domains/hosters.txt) | 175 |

## How domains are added to the blocklist

- The retrieval process searches Google with a list of search terms almost exclusively used in scam sites. See the list of search terms here: [search_terms.txt](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/search_terms.txt)
- Domains are filtered against a whitelist (scam reporting sites, forums, genuine stores, etc.), along with other filtering
- Domains found in the Cisco Umbrella 1M toplist are checked manually (checked during retrieval and toplist updates)

To see the full filtering and retrieval process check out the code in the repository.

Malicious domains found in [r/Scams](https://www.reddit.com/r/Scams) are occasionally added after being manually vetted.

Domains are retrieved from multiple regions such as Asia, Europe, and North America.

## Why the Domains and Host formats are not supported

Malicious domains often have [wildcard DNS records](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/) that allow scammers to create large amounts of subdomains. Often, these subdomains are random strings such as `kwsjla.scam.com`. To find and add individual subdomains would require much effort and inflate the blocklist size.

Only formats that make use of wildcard matching are supported as they can block all subdomains. This allows for further optimisations explained below.

## Optimisations

The blocklist maintenance process from domain retrieval to list building makes use of wildcard blocking in these ways:

1. Removal of redundant entries: if the blocklist contains `spam.com`, via wildcard matching, `sub.spam.com` would be blocked as well and is, therefore, redundant and will be removed.

2. Blocking common second-level domains/malicious hosters: if `abc.spam.com` and `def.spam.com` are both present in the blocklist, they are replaced with `spam.com` to block all subdomains instead of having separate entries for each subdomain. A whitelist is used for genuine e-commerce/hosting domains such as `myshopify.com`. This is an effective way to block malicious hosting domains that host scam/malicious sites on their subdomains. This process is done manually and never unattended.

3. TLD-based detection of malicious hosters: the list of common second-level domains from (2) is used to gather statistics on frequently used TLDs. These TLDs are factored into the domain retrieval process to point out potential malicious hosting domains. The current process uses the TLDs that makeup 5% or more of common second-level domains in the list. These calculated TLDs are then compared to new entries during the retrieval process where flagged domains can be manually added to the blocklist. This process is done manually and never unattended.

## Dead domains

Domains returning `NXDOMAIN` are removed during the domain retrieval process and once a day for the full blocklist. Dead domains that resolve again are added back.

## Inspiration

After browsing r/Scams for weeks and manually reporting scam sites to Hagezi's issue tracker, I realized most scam sites follow a similar template.

Although I could never keep up with the number of scam sites created daily, I aim to retrieve as many new scam sites as possible with this project.

## Limitations

Most of the domains retrieved are from manually running the script on my phone's terminal emulator. After successive runs, a VPN server change is required to overcome Google's IP blocking.

As such, the number of domains added to the blocklist in a day varies depending on my interest and free time. However, if left unattended, the blocklist is still capable of automatic daily updates via Github Workflows. The retrieval workflow is ran only once a day to prevent getting blocked by Google. Therefore, automatic updates have a lower daily retrieval count than manually running throughout the day.

## See also

[Durablenapkin's Scam Blocklist](https://github.com/durablenapkin/scamblocklist)

[Hagezi's Fake list](https://github.com/hagezi/dns-blocklists#fake) (uses my list as a source)

[Elliotwutingfeng's Global Anti Scam Organization blocklist](https://github.com/elliotwutingfeng/GlobalAntiScamOrg-blocklist)

[r/Scams subreddit](https://www.reddit.com/r/Scams)

## Resources

[ShellCheck](https://www.shellcheck.net/): shell script checker

[LinuxCommand's Coding Standards](https://linuxcommand.org/lc3_adv_standards.php): shell script coding standard

[Hagezi's DNS Blocklist](https://github.com/hagezi/dns-blocklists): inspiration and reference

[TurboGPT](https://turbogpt.ai/): ChatGPT client I used for generating ideas for tricky code

[Grammarly](https://www.grammarly.com): grammar correction and suggestions for README files, comments, etc.

### Appreciation

Thanks to the following people for the help, inspiration, and support!

[@hagezi](https://github.com/hagezi)

[@iam-py-test](https://github.com/iam-py-test)

[@bongochong](https://github.com/bongochong)

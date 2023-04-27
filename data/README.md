# Scam Blocklist

| Syntax | Entries |
| --- |:---:|
| [Adblock Plus](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/adblock.txt) | adblock_count |
| [Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/domains.txt) | domains_count |

Unique scam sites found yesterday: found_yest

Updated: update_time

### How domains are added to the blocklist

- The script searches Google with a list of search terms almost exclusively used in scam sites
- Invalid entries (non domains) are removed
- Domains are filtered against a whitelist (scam reporting sites, forums, genuine stores, etc.)
- Domains with whitelisted TLDs (edu, gov) are removed
- Domains are compared against the Cisco Umbrella Toplist
- Domains found in the toplist are checked manually
- Dead domains are removed
- Resolving `www` subdomains are included in the domains list
- Domains that are found in toplist/whitelist updates are vetted manually

Malicious domains found in [r/Scams](https://www.reddit.com/r/Scams) are also added after being manually vetted.

### Goal

Identify newly created scam sites that use the same template as reported scam sites.

### See also

[Durablenapkin's Scam Blocklist](https://github.com/durablenapkin/scamblocklist)

[Hagezi's Fake list](https://github.com/hagezi/dns-blocklists#fake) (Contains both my list and Durablenapkin's list)

### Top scam TLDs

| TLD | Count |
| ---:|:--- |
top_tlds

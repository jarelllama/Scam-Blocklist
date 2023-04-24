Current number of domains: `3736`

https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/domains

### How domains are added to the blocklist

- The script searches Google with a list of search terms almost exclusively used in scam sites
- Invalid entries (non domains) are removed
- Domains are filtered against a whitelist (scam reporting sites, forums, genuine stores, etc.)
- Domains with whitelisted TLDs are removed
- Domains are compared against the Umbrella Toplist
- Domains found in the toplist are checked manually
- Dead domains are removed
- Domains that are found in toplist updates are vetted

Resolving `www` subdomains are included. This is so lists that don't support wildcards (Pihole) can block both `example.com` and `www.example.com`.

Some malicious domains found in r/Scams are also added after being manually vetted.

### Goal

Identify newly created scam sites that use the same template as reported scam sites.

### See also

[Durablenapkin's Scam Blocklist](https://github.com/durablenapkin/scamblocklist)

[Hagezi's Fake list](https://github.com/hagezi/dns-blocklists#fake) (Contains both my list and Durablenapkin's list)

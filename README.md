### How domains are added to the blocklist

- The script searches Google with a list of search terms almost exclusively used in scam sites
- Invalid entries (non domains) are removed
- Domains are filtered against a whitelist (scam reporting sites, forums, genuine stores, etc.)
- Domains with whitelisted TLDs are removed
- Domains are compared against the Umbrella Toplist
- Domains found in the toplist are checked manually
- Dead domains are removed
- Domains that are found in toplist updates are checked

Note that when `www` subdomains are retrieved the script adds the www-stripped domain alongside the `www` subdomain. This is so wildcard supporting formats can block all subdomains while lists that don't support wildcards (Pihole) can block both `example.com` and `www.example.com`.

### Goal

Identify newly created scam sites that use the same template as reported scam sites.

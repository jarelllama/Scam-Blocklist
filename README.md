### How domains are added to the blocklist

- The script searches Google with a list of search terms almost exclusively used in scam sites
- The unique domains extracted are added to a pending domain list
- The pending domains are sorted alphabetically
- Invalid entries (non domains) are removed
- Domains with whitelisted TLDs are removed
- Domains are filtered against a whitelist (scam reporting sites, forums, genuine stores, etc.)
- The filtered pending domains list is compared against the Umbrella Toplist
- Domains found in the toplist are checked manually
- The final list of pending domains are merged to the blocklist

### Goal

Identify newly created scam sites that use the same template as reported scam sites.

# Scam Blocklist

| Syntax | Entries |
| --- |:---:|
| [Adblock Plus](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/adblock.txt) | 2417 |
| [Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/domains.txt) | 4811 |

Unique scam sites found yesterday: 39

Updated: Fri Apr 28 08:17 UTC

### How domains are added to the blocklist

- The script searches Google with a list of search terms almost exclusively used in scam sites
- Domains are filtered against a whitelist (scam reporting sites, forums, genuine stores, etc.), along with other filtering
- Domains are compared against the Cisco Umbrella Toplist
- Domains found in the toplist are checked manually
- Dead domains are removed
- Resolving `www` subdomains are included in the domains list
- Domains that are found in toplist/whitelist updates are vetted manually

Malicious domains found in [r/Scams](https://www.reddit.com/r/Scams) are also added after being manually vetted.

To see the full filtering process check out the code in the repository.

### Inspiration

After browsing r/Scams for weeks and manually reporting scam sites to Hagezi's issue tracker, I realised most scam sites follow a similar template.

There is no way I can keep up with the amount of scam sites created daily but with this project I aim to retrieve as many newly created scam sites as possible.

### See also

[Durablenapkin's Scam Blocklist](https://github.com/durablenapkin/scamblocklist)

[Hagezi's Fake list](https://github.com/hagezi/dns-blocklists#fake) (Contains both my list and Durablenapkin's list)

### Top scam TLDs

| TLD | Count |
| ---:|:--- |
| com  | 3256 |
| shop  | 572 |
| store  | 341 |
| online  | 74 |
| net  | 66 |
| xyz  | 64 |
| space  | 56 |
| us  | 46 |
| website  | 38 |
| top  | 34 |

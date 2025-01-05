# Jarelllama's Scam Blocklist

Blocklist for newly created scam, phishing, and malware domains automatically retrieved daily using Google Search API, automated detection, and public databases.

This blocklist aims to detect new malicious domains within a short period of their registration date. Since the project began, the blocklist has expanded to include not only scam websites but also malware domains.

For extended protection, use [xRuffKez's NRD Lists](https://github.com/xRuffKez/NRD) to block all newly registered domains (NRDs), and [Hagezi's Threat Intelligence Feed](https://github.com/hagezi/dns-blocklists?tab=readme-ov-file#tif) (full version) which includes this blocklist.

Sources include:

- Public databases
- Google Search indexing to find common scam site templates
- Detection of common cybersquatting techniques like typosquatting, doppelganger domains, and IDN homograph attacks using [dnstwist](https://github.com/elceef/dnstwist) and [URLCrazy](https://github.com/urbanadventurer/urlcrazy)
- Domain generation algorithm (DGA) domain detection using [DGA Detector](https://github.com/exp0se/dga_detector)
- Regex expression matching for phishing NRDs. See the list of expressions [here](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/phishing_targets.csv)

A list of all sources can be found in [SOURCES.md](https://github.com/jarelllama/Scam-Blocklist/blob/main/SOURCES.md).

The automated retrieval is done daily at 16:00 UTC.

## Downloads

| Format | Syntax |
| --- | --- |
| [Adblock Plus](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/adblock/scams.txt) | \|\|scam.com^ |
| [Wildcard Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_domains/scams.txt) | scam.com |

## Statistics

``` text
Total domains: 223321
Light version: 21054

New domains after filtering:
Today | Monthly | %Monthly | %Filtered | Source
    0 |     247 |      1 % |      37 % | 165 Anti-fraud
   51 |     209 |      1 % |      12 % | Artists Against 419
    0 |       7 |      0 % |      39 % | Česká Obchodní Inspekce
   34 |     296 |      1 % |       1 % | Cybersquatting
  855 |    5201 |     31 % |       0 % | DGA Detector
   48 |      98 |      0 % |      19 % | Emerging Threats
    0 |       0 |      0 % |      20 % | FakeWebshopListHUN
   57 |     354 |      2 % |       3 % | Google Search
  153 |     729 |      4 % |      10 % | Gridinsoft
  288 |    3816 |     22 % |      10 % | Jeroengui
   21 |     317 |      1 % |       0 % | Jeroengui (NRDs)
  357 |    1831 |     11 % |      26 % | PhishStats
   29 |     174 |      1 % |       0 % | PhishStats (NRDs)
    0 |      14 |      0 % |      12 % | PuppyScams.org
  829 |    3723 |     22 % |       1 % | Regex Matching
    0 |      39 |      0 % |       7 % | Scam Directory
    0 |       0 |      0 % |      32 % | ScamAdviser
    0 |       0 |      0 % |       5 % | StopGunScams.com
    0 |       8 |      0 % |       5 % | Verbraucherzentrale Hamburg
    0 |       0 |      0 % |      31 % | ViriBack C2 Tracker
 2675 |   16594 |    100 % |      22 % | All sources

- %Monthly: percentage out of total domains from all sources.
- %Filtered: percentage of dead, whitelisted, and parked domains.

Dead domains removed today: 3737
Resurrected domains added today: 990

Parked domains removed this month: 0
Unparked domains added today: 60
```

<details>
<summary>Domains over time (days)</summary>

![Domains over time](https://raw.githubusercontent.com/iam-py-test/blocklist_stats/main/stats/Jarelllamas_Scam_Blocklist.png)

Courtesy of iam-py-test/blocklist_stats.
</details>

## Automated filtering process

- Domains are filtered against an actively maintained whitelist
- Domains are checked against the [Tranco Top Sites Ranking](https://tranco-list.eu/) for potential false positives which are then vetted manually
- Common subdomains like 'www' are stripped
- Non-domain entries are removed
- Redundant rules are removed via wildcard matching. For example, 'abc.example.com' is a wildcard match of 'example.com' and, therefore, is redundant and removed. Wildcards are occasionally added to the blocklist manually to further optimize the number of entries

Entries that require manual verification/intervention are notified to the maintainer for fast remediations.

The full filtering process can be viewed in the repository's code.

### Dead domains

Dead domains are removed daily using AdGuard's [Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter).

Dead domains that are resolving again are included back into the blocklist.

### Parked domains

Parked domains are removed weekly while unparked domains are added back daily. A list of common parked domain messages is used to automatically detect parked domains. This list can be viewed here: [parked_terms.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/parked_terms.txt).

Parked sites no longer containing any of the parked messages are assumed to be unparked.

## Other blocklists

### Light version

For collated blocklists cautious about size, a light version of the blocklist is available in the [lists](https://github.com/jarelllama/Scam-Blocklist/tree/main/lists) directory. Sources excluded from the light version are marked in [SOURCES.md](https://github.com/jarelllama/Scam-Blocklist/blob/main/).

Note that dead and parked domains that become alive/unparked are not added back into the light version due to limitations in how these domains are recorded.

### NSFW Blocklist

A blocklist for NSFW domains is available in Adblock Plus format here:
[nsfw.txt](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/adblock/nsfw.txt).

<details>
<summary>Details</summary>
<ul>
<li>Domains are automatically retrieved from the Tranco Top Sites Ranking daily</li>
<li>Dead domains are removed daily</li>
<li>Note that resurrected domains are not added back</li>
<li>Note that parked domains are not checked for</li>
</ul>
Total domains: 12906
<br>
<br>
This blocklist does not just include adult videos, but also NSFW content of the artistic variety (rule34, illustrations, etc).
</details>

### Parked domains

For list maintainers interested in using the parked domains as a source, the list of parked domains can be found here: [parked_domains.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/data/parked_domains.txt). This list is capped at 50,000 domains.

## Resources / See also

- [AdGuard's Hostlist Compiler](https://github.com/AdguardTeam/HostlistCompiler): simple tool that compiles hosts blocklists and removes redundant rules
- [Elliotwutingfeng's repositories](https://github.com/elliotwutingfeng?tab=repositories): various original blocklists
- [Google's Shell Style Guide](https://google.github.io/styleguide/shellguide.html): Shell script style guide
- [Grammarly](https://grammarly.com/): spelling and grammar checker
- [Hagezi's DNS Blocklists](https://github.com/hagezi/dns-blocklists): various curated blocklists including threat intelligence feeds
- [Jarelllama's Blocklist Checker](https://github.com/jarelllama/Blocklist-Checker): generate a simple static report for blocklists or see previous reports of requested blocklists
- [ShellCheck](https://github.com/koalaman/shellcheck): static analysis tool for Shell scripts
- [VirusTotal](https://www.virustotal.com/): analyze suspicious files, domains, IPs, and URLs to detect malware (also includes WHOIS lookup)
- [iam-py-test/blocklist_stats](https://github.com/iam-py-test/blocklist_stats): statistics on various blocklists

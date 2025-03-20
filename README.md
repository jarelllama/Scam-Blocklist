# Jarelllama's Scam Blocklist

Blocklist for newly created scam, phishing, and other malicious domains automatically retrieved daily using Google Search API, automated detection, and public databases.

This blocklist aims to detect new malicious domains within a short period of their registration date. Since the project began, the blocklist has expanded to include not only scam/phishing websites but also domains for:

- Malware
- Command and Control servers
- Adware
- Browser hijackers

For extended protection, use [xRuffKez's NRD Lists](https://github.com/xRuffKez/NRD) to block all newly registered domains (NRDs), and [Hagezi's Threat Intelligence Feed](https://github.com/hagezi/dns-blocklists?tab=readme-ov-file#tif) (full version) which includes this blocklist.

Sources for this blocklist include:

- Public databases
- Google Search indexing to find common scam site templates
- Detection of common cybersquatting techniques like typosquatting, doppelganger domains, and IDN homograph attacks using [dnstwist](https://github.com/elceef/dnstwist) and [URLCrazy](https://github.com/urbanadventurer/urlcrazy)
- Domain generation algorithm (DGA) domain detection using [DGA Detector](https://github.com/exp0se/dga_detector)
- Regex expression matching for phishing NRDs. See the list of expressions [here](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/phishing_detection.csv)

A list of all sources can be found in [SOURCES.md](https://github.com/jarelllama/Scam-Blocklist/blob/main/SOURCES.md).

The automated retrieval is done daily at 16:00 UTC.

## Downloads

| Format | Syntax |
| --- | --- |
| [Adblock Plus](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/adblock/scams.txt) | \|\|scam.com^ |
| [Wildcard Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_domains/scams.txt) | scam.com |

## Statistics

``` text
Total domains: 468729
Light version: 18254

New domains after filtering:
Today | Monthly | %Monthly | %Filtered | Source
    - |     751 |      0 % |      34 % | 165 Anti-fraud
    - |     193 |      0 % |      13 % | Artists Against 419
    - |      40 |      0 % |      11 % | BehindMLM
    - |      97 |      0 % |       4 % | BugsFighter
    - |     455 |      0 % |      11 % | Chainabuse
    - |     389 |      0 % |      55 % | DFPI Crypto Scam Tracker
    - |   22810 |     18 % |       1 % | DGA Detector
    - |    1022 |      0 % |       0 % | dnstwist
    - |    3931 |      3 % |      35 % | Emerging Threats
    - |    1273 |      1 % |      25 % | FakeWebshopListHUN
    - |    1243 |      1 % |       2 % | Google Search
    - |    4992 |      4 % |      18 % | Gridinsoft
    - |   25577 |     20 % |       8 % | Jeroengui
    - |       0 |      0 % |       0 % | Jeroengui (NRDs)
    - |    3145 |      2 % |      21 % | Malwarebytes
    - |     325 |      0 % |       8 % | MalwareURL
    - |      52 |      0 % |       7 % | PCrisk
    - |   24804 |     20 % |      28 % | PhishStats
    - |      51 |      0 % |      18 % | PuppyScams.org
    - |   23636 |     19 % |       1 % | Regex
    - |    2641 |      2 % |       3 % | SafelyWeb
    - |    2398 |      1 % |      38 % | Scam Directory
    - |      14 |      0 % |      30 % | ScamAdviser
    - |     820 |      0 % |       5 % | ScamMinder
    - |      21 |      0 % |      10 % | ScamScavenger
    - |     519 |      0 % |      15 % | ScamTracker
    - |     100 |      0 % |       6 % | Unit42
    - |     156 |      0 % |       4 % | URLCrazy
    - |      24 |      0 % |      11 % | Verbraucherzentrale Hamburg
    - |      70 |      0 % |      28 % | ViriBack C2 Tracker
    - |     216 |      0 % |      20 % | Wildcat Cyber Patrol
    - |      18 |      0 % |       8 % | WiperSoft
    - |     514 |      0 % |      49 % | Česká Obchodní Inspekce
    - |  122518 |    100 % |       0 % | All sources

- %Monthly: percentage out of total domains from all sources.
- %Filtered: percentage of dead, whitelisted, and parked domains.

Dead domains removed today: 14731
Dead domains removed this month: 110583
Resurrected domains added today: 2415

Parked domains removed today: 1666
Parked domains removed this month: 29431
Unparked domains added today: 2184
```

<details>
<summary>Domains over time (days)</summary>

![Domains over time](https://raw.githubusercontent.com/iam-py-test/blocklist_stats/main/stats/Jarelllamas_Scam_Blocklist.png)

Courtesy of iam-py-test/blocklist_stats.
</details>

## Automated filtering process

- Domains are filtered against an actively maintained whitelist
- Domains are checked against the [Tranco Top Sites Ranking](https://tranco-list.eu/) for potential false positives which are then vetted manually
- Non-domain entries are removed
- Wildcards are automatically added to optimize the size of the blocklist
- Subdomains are automatically discovered and stripped for better wildcard matching

Entries that require manual verification/intervention are notified to the maintainer for fast remediations.

The full filtering process can be viewed in the repository's code.

### Dead domains

Dead domains are removed daily using AdGuard's [Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter).

Dead domains that are resolving again are included back into the blocklist.

### Parked domains

Parked domains are removed daily. A list of common parked domain messages is used to automatically detect these domains. This list can be viewed here: [parked_terms.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/parked_terms.txt).

Parked sites no longer containing any of the parked messages are assumed to be unparked and are included back into the blocklist.

## Other blocklists

### Light version

For collated blocklists cautious about size, a light version of the blocklist is available in the [lists](https://github.com/jarelllama/Scam-Blocklist/tree/main/lists) directory. Sources excluded from the light version are marked in [SOURCES.md](https://github.com/jarelllama/Scam-Blocklist/blob/main/SOURCES.md). The light version also includes domains from the full version that are found in the Tranco toplist.

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
Total domains: 13786
<br>
<br>
This blocklist does not just include adult videos, but also NSFW content of the artistic variety (rule34, illustrations, etc).
</details>

### Parked domains

For list maintainers interested in using the parked domains as a source, the list of parked domains can be found here: [parked_domains.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/data/parked_domains.txt). This list is capped at 100,000 domains.

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

# Jarelllama's Scam Blocklist

Blocklist for newly created scam and phishing domains automatically retrieved daily using Google Search API, automated detection, and other public sources.

This blocklist aims to be an alternative to blocking all newly registered domains (NRDs) seeing how many, but not all, NRDs are malicious. This is done by detecting new malicious domains within a short period of their registration date.
Sources include:

- Public databases
- Google Search indexing to find common scam site templates
- Open source tools such as [dnstwist](https://github.com/elceef/dnstwist) to detect cybersquatting techniques like typosquatting, doppelganger domains, and IDN homograph attacks
- Regex expression matching for phishing NRDs. See the list of expressions [here](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/phishing_targets.csv)

A list of all sources can be found in [SOURCES.md](https://github.com/jarelllama/Scam-Blocklist/blob/main/SOURCES.md) with config files [here](https://github.com/jarelllama/Scam-Blocklist/tree/main/config).

The automated retrieval is done daily at 16:00 UTC.

## Downloads

| Format | Syntax |
| --- | --- |
| [Adblock Plus](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/adblock/scams.txt) | \|\|scam.com^ |
| [Wildcard Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_domains/scams.txt) | scam.com |

This blocklist is integrated into [Hagezi's Threat Intelligence Feed](https://github.com/hagezi/dns-blocklists?tab=readme-ov-file#tif) (full version). For extended protection, please use his list instead.

## Statistics

``` text
Total domains: 178999
Light version: 18036

New domains after filtering:
Today | Monthly | %Monthly | %Filtered | Source
   26 |    2000 |      2 % |      33 % | Emerging Threats
    0 |    2148 |      2 % |      18 % | FakeWebshopListHUN
   17 |     463 |      0 % |       3 % | Google Search
  666 |   16082 |     20 % |       9 % | Jeroengui phishing feed
    7 |     106 |      0 % |       7 % | Jeroengui scam feed
  255 |   35712 |     44 % |      22 % | PhishStats
   25 |    9440 |     11 % |       0 % | PhishStats (NRDs)
  713 |   20610 |     25 % |       1 % | Regex Matching (NRDs)
   43 |     197 |      0 % |      11 % | aa419.org
   23 |     963 |      1 % |       1 % | dnstwist (NRDs)
    0 |    1478 |      1 % |      32 % | guntab.com
    0 |     166 |      0 % |       8 % | scam.directory
    0 |      46 |      0 % |      32 % | scamadviser.com
    0 |       8 |      0 % |       5 % | stopgunscams.com
 1750 |   80283 |    100 % |      19 % | All sources

- %Monthly: percentage out of total domains from all sources.
- %Filtered: percentage of dead, whitelisted and parked domains.
```

<details>
<summary>Domains over time (days)</summary>

![Domains over time](https://raw.githubusercontent.com/iam-py-test/blocklist_stats/main/stats/Jarelllamas_Scam_Blocklist.png)

Courtesy of iam-py-test/blocklist_stats.
</details>

## Other blocklists

### Light version

For collated blocklists cautious about size, a light version of the blocklist is available in the [lists](https://github.com/jarelllama/Scam-Blocklist/tree/main/lists) directory. Sources excluded from the light version are marked in [SOURCES.md](https://github.com/jarelllama/Scam-Blocklist/blob/main/).

Note that dead and parked domains that become alive/unparked are not added back into the light version due to limitations in the way these domains are recorded.

### NSFW Blocklist

A blocklist for NSFW domains is available in Adblock Plus format here:
[nsfw.txt](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/adblock/nsfw.txt).

<details>
<summary>Details</summary>
<ul>
<li>Domains are automatically retrieved from the Tranco Top Sites Ranking daily</li>
<li>Dead domains are removed daily</li>
<li>Note that resurrected domains are not added back into the blocklist</li>
<li>Note that parked domains are not checked for in this blocklist</li>
</ul>
Total domains: 12530
<br>
<br>
This blocklist does not just include adult videos, but also NSFW content of the artistic variety (rule34, illustrations, etc).
</details>

### Malware Blocklist

A blocklist for malicious domains extracted from Proofpoint's [Emerging Threats](https://rules.emergingthreats.net/) rulesets can be found here: **[jarelllama/Emerging-Threats](https://github.com/jarelllama/Emerging-Threats)**.

## Automated filtering process

- Domains are filtered against an actively maintained whitelist
- Domains are checked against the [Tranco Top Sites Ranking](https://tranco-list.eu/) for potential false positives which are then vetted manually
- Common subdomains like 'www' are stripped
- Only domains are included in the blocklist; URLs are stripped down to their domains and IP addresses are manually checked for resolving DNS records
- Redundant rules are removed via wildcard matching. For example, 'abc.example.com' is a wildcard match of 'example.com' and, therefore, is redundant and removed. Wildcards are occasionally added to the blocklist manually to further optimize the number of entries

Entries that require manual verification/intervention are notified to the maintainer for fast remediations.

The full filtering process can be viewed in the repository's code.

### Dead domains

Dead domains are removed daily using AdGuard's [Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter).

Dead domains that are resolving again are included back into the blocklist.

``` text
Dead domains removed today: 509
Resurrected domains added today: 483
```

### Parked domains

Parked domains are removed weekly. A list of common parked domain messages is used to automatically detect these domains. This list can be viewed here: [parked_terms.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/parked_terms.txt).

Parked sites no longer containing any of the parked messages are assumed to be unparked and are included back into the blocklist.

> [!TIP]
For list maintainers interested in integrating the parked domains as a source, a list of weekly-updated parked domains can be found here: [parked_domains.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/data/parked_domains.txt) (capped to newest 50000 entries).

``` text
Parked domains removed this month: 15835
Unparked domains added this month: 517
```

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

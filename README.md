# Jarelllama's Scam Blocklist

Blocklist for newly created scam and phishing domains automatically retrieved daily using Google Search API, automated detection, and other public sources.

This blocklist aims to be an alternative to blocking all newly registered domains (NRDs) seeing how many, but not all, NRDs are malicious. This is done by detecting new malicious domains within a short period of their registration date.
Sources include:

- Public databases
- Google Search indexing to find common scam site templates
- Open source tools such as [dnstwist](https://github.com/elceef/dnstwist) to detect common cybersquatting techniques like typosquatting, doppelganger Domains, and IDN homograph attacks
- Regex expression matching for phishing NRDs

A list of all sources can be found in [SOURCES.md](https://github.com/jarelllama/Scam-Blocklist/blob/main/SOURCES.md) with config files [here](https://github.com/jarelllama/Scam-Blocklist/tree/main/config).

The automated retrieval is done daily at 16:00 UTC.

## Download

| Format | Syntax |
| --- | --- |
| [Adblock Plus](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/adblock/scams.txt) | \|\|scam.com^ |
| [Wildcard Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_domains/scams.txt) | scam.com |

## Statistics

``` text
Total domains: 163690
Light version: 15877

New domains from each source: *
Today | Yesterday | Excluded | Source
  868 |       307 |      18% | FakeWebshopListHUN
   29 |        27 |       3% | Google Search
  842 |      1300 |       8% | Jeroengui phishing feed
    9 |         8 |       7% | Jeroengui scam feed
    0 |      4679 |      19% | PhishStats
    0 |      1461 |       0% | PhishStats (NRDs)
 2584 |      3186 |       1% | Regex Matching (NRDs)
   19 |         9 |      10% | aa419.org
  258 |        73 |       1% | dnstwist (NRDs)
  496 |       170 |      31% | guntab.com
    6 |        49 |       8% | scam.directory
   14 |         8 |      31% | scamadviser.com
    2 |         1 |       5% | stopgunscams.com
 5127 |      9818 |      17% | All sources

- The new domain numbers reflect what was retrieved, not
 what was added to the blocklist.
- The excluded % is of domains that are dead, whitelisted, or parked.
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
Total domains: 12374
<br>
<br>
This blocklist does not just include adult videos, but also NSFW content of the artistic variety (rule34, illustrations, etc).
</details>

### Malware Blocklist

A blocklist for malicious domains extracted from Proofpoint's [Emerging Threats](https://rules.emergingthreats.net/) rulesets can be found here: **[jarelllama/Emerging-Threats](https://github.com/jarelllama/Emerging-Threats)**.

## Automated filtering process

- The domains collated from all sources are filtered against an actively maintained whitelist (scam reporting sites, forums, vetted stores, etc.)
- The domains are checked against the [Tranco Top Sites Ranking](https://tranco-list.eu/) for potential false positives which are then vetted manually
- Common subdomains like 'www' are stripped. The list of subdomains checked for can be viewed here: [subdomains.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/subdomains.txt)
- Only domains are included in the blocklist; URLs are stripped down to their domains and IP addresses are manually checked for resolving DNS records
- Redundant rules are removed via wildcard matching. For example, 'abc.example.com' is a wildcard match of 'example.com' and, therefore, is redundant and removed. Wildcards are occasionally added to the blocklist manually to further optimize the number of entries

Entries that require manual verification/intervention are notified to the maintainer for fast remediations.

The full filtering process can be viewed in the repository's code.

### Dead domains

Dead domains are removed daily using AdGuard's [Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter).

Dead domains that are resolving again are included back into the blocklist.

``` text
Dead domains removed today: 3239
Resurrected domains added today: 472
```

### Parked domains

Parked domains are removed weekly. A list of common parked domain messages is used to automatically detect these domains. This list can be viewed here: [parked_terms.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/parked_terms.txt).

Parked sites no longer containing any of the parked messages are assumed to be unparked and are included back into the blocklist.

> [!TIP]
For list maintainers interested in integrating the parked domains as a source, a list of weekly-updated parked domains can be found here: [parked_domains.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/data/parked_domains.txt) (capped to newest 50000 entries).

``` text
Parked domains removed this month: 13470
Unparked domains added this month: 456
```

## As seen in

- [Fabriziosalmi's Hourly Updated Domains Blacklist](https://github.com/fabriziosalmi/blacklists)
- [Hagezi's Threat Intelligence Feeds](https://github.com/hagezi/dns-blocklists?tab=readme-ov-file#closed_lock_with_key-threat-intelligence-feeds---increases-security-significantly-recommended-)
- [Sefinek24's blocklist generator and collection](https://blocklist.sefinek.net/)
- [T145's Black Mirror](https://github.com/T145/black-mirror)
- [The oisd blocklist](https://oisd.nl/)
- [doh.tiar.app privacy DNS](https://doh.tiar.app/)
- [dnswarden privacy-focused DNS](https://dnswarden.com/)
- [file-git.trli.club](https://file-git.trli.club/)
- [iam-py-test/my_filters_001](https://github.com/iam-py-test/my_filters_001)

## Resources / See also

- [AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter): simple tool to check adblock filtering rules for dead domains
- [AdGuard's Hostlist Compiler](https://github.com/AdguardTeam/HostlistCompiler): simple tool that compiles hosts blocklists and removes redundant rules
- [Elliotwutingfeng's repositories](https://github.com/elliotwutingfeng?tab=repositories): various original blocklists
- [Google's Shell Style Guide](https://google.github.io/styleguide/shellguide.html): Shell script style guide
- [Grammarly](https://grammarly.com/): spelling and grammar checker
- [Jarelllama's Blocklist Checker](https://github.com/jarelllama/Blocklist-Checker): generate a simple static report for blocklists or see previous reports of requested blocklists
- [ShellCheck](https://github.com/koalaman/shellcheck): static analysis tool for Shell scripts
- [Tranco](https://tranco-list.eu/): research-oriented top sites ranking hardened against manipulation
- [VirusTotal](https://www.virustotal.com/): analyze suspicious files, domains, IPs, and URLs to detect malware (also includes WHOIS lookup)
- [iam-py-test/blocklist_stats](https://github.com/iam-py-test/blocklist_stats): statistics on various blocklists

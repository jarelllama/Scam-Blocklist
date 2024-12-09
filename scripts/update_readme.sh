#!/bin/bash

# Updates the README.md content and statistics.

# TODO: mawk '{sum += $1} END {print sum}' can be used to print 0 when there is no value.

update_readme() {
    cat << EOF > README.md
# Jarelllama's Scam Blocklist

${BLOCKLIST_DESCRIPTION}

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

## Statistics

\`\`\` text
Total domains: $(grep -cF '||' lists/adblock/scams.txt)
Light version: $(grep -cF '||' lists/adblock/scams_light.txt)

New domains after filtering: *
Today | Monthly | %Monthly | %Filtered | Source
$(print_stats 'Emerging Threats')
$(print_stats FakeWebshopListHUN)
$(print_stats 'Google Search')
$(print_stats 'Jeroengui phishing') feed
$(print_stats 'Jeroengui scam') feed
$(print_stats PhishStats)
$(print_stats 'PhishStats (NRDs)')
$(print_stats Regex) Matching (NRDs)
$(print_stats aa419.org)
$(print_stats dnstwist) (NRDs)
$(print_stats guntab.com)
$(print_stats scam.directory)
$(print_stats scamadviser.com)
$(print_stats stopgunscams.com)
$(print_stats)

- %Monthly: percentage out of total domains from all sources.
- %Filtered: percentage of dead, whitelisted and parked domains.
\`\`\`

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
Total domains: $(grep -cF '||' lists/adblock/nsfw.txt)
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

\`\`\` text
Dead domains removed today: $(mawk "/${TODAY},dead_count/" "$DOMAIN_LOG" | csvcut -c 3)
Resurrected domains added today: $(mawk "/${TODAY},resurrected_count/" "$DOMAIN_LOG" | csvcut -c 3)
\`\`\`

### Parked domains

Parked domains are removed weekly. A list of common parked domain messages is used to automatically detect these domains. This list can be viewed here: [parked_terms.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/parked_terms.txt).

Parked sites no longer containing any of the parked messages are assumed to be unparked and are included back into the blocklist.

> [!TIP]
For list maintainers interested in integrating the parked domains as a source, a list of weekly-updated parked domains can be found here: [parked_domains.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/data/parked_domains.txt) (capped to newest 50000 entries).

\`\`\` text
Parked domains removed this month: $(mawk "/${THIS_MONTH},parked_count/" "$DOMAIN_LOG" | csvcut -c 3 | mawk '{sum += $1} END {print sum}')
Unparked domains added this month: $(mawk "/${THIS_MONTH},unparked_count/" "$DOMAIN_LOG" | csvcut -c 3 | mawk '{sum += $1} END {print sum}')
\`\`\`

## Resources / See also

- [AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter): simple tool to check adblock filtering rules for dead domains
- [AdGuard's Hostlist Compiler](https://github.com/AdguardTeam/HostlistCompiler): simple tool that compiles hosts blocklists and removes redundant rules
- [Elliotwutingfeng's repositories](https://github.com/elliotwutingfeng?tab=repositories): various original blocklists
- [Google's Shell Style Guide](https://google.github.io/styleguide/shellguide.html): Shell script style guide
- [Grammarly](https://grammarly.com/): spelling and grammar checker
- [Hagezi's DNS Blocklists](https://github.com/hagezi/dns-blocklists): various curated blocklists including threat intelligence feeds
- [Jarelllama's Blocklist Checker](https://github.com/jarelllama/Blocklist-Checker): generate a simple static report for blocklists or see previous reports of requested blocklists
- [ShellCheck](https://github.com/koalaman/shellcheck): static analysis tool for Shell scripts
- [Tranco](https://tranco-list.eu/): research-oriented top sites ranking hardened against manipulation
- [VirusTotal](https://www.virustotal.com/): analyze suspicious files, domains, IPs, and URLs to detect malware (also includes WHOIS lookup)
- [iam-py-test/blocklist_stats](https://github.com/iam-py-test/blocklist_stats): statistics on various blocklists
EOF
}

readonly FUNCTION='bash scripts/tools.sh'
readonly SOURCE_LOG='config/source_log.csv'
readonly DOMAIN_LOG='config/domain_log.csv'
TODAY="$(TZ=Asia/Singapore date +"%d-%m-%y")"
THIS_MONTH="$(TZ=Asia/Singapore date +"%m-%y")"

# Function 'print_stats' is an echo wrapper that returns the formatted
# statistics for the given source.
#   $1: source to process (default is all sources)
print_stats() {
    this_month="$(sum "$THIS_MONTH" "$1")"
    total_this_month="$(sum "$THIS_MONTH")"

    printf "%5s |%8s |%8s %% |%9s %% | %s" \
        "$(sum "$TODAY" "$1")" "$this_month" \
        "$(( this_month * 100 / total_this_month ))" "$(sum_excluded "$1" )" "${1:-All sources}"
}

# Note that csvkit is used in the following functions as the Google Search
# search terms may contain commas which makes using mawk complicated.

# Function 'sum' is an echo wrapper that returns the total sum of domains
# retrieved by the given source for that timeframe.
#   $1: day to process
#   $2: source to process (default is all sources)
sum() {
    # Print dash if no runs for that day found
    ! grep -qF "$1" "$SOURCE_LOG" && { printf "-"; return; }

    # grep used here as mawk has issues with brackets after whitespaces
    grep "${1},${2}.*,saved$" "$SOURCE_LOG" | csvcut -c 5 \
        | mawk '{sum += $1} END {print sum}'
}

# Function 'sum_excluded' is an echo wrapper that returns the percentage of
# excluded domains out of the raw count retrieved by the given source.
#   $1: source to process (default is all sources)
sum_excluded() {
    # Get required columns of the source (includes unsaved)
    grep -F "$1" "$SOURCE_LOG" | csvcut -c 4,6,7,8 > rows.tmp

    raw_count="$(mawk -F ',' '{sum += $1} END {print sum}' rows.tmp)"
    # Return if raw count is 0 to avoid divide by zero error
    (( raw_count == 0 )) && { printf "0"; return; }

    white_count="$(mawk -F ',' '{sum += $2} END {print sum}' rows.tmp)"
    dead_count="$(mawk -F ',' '{sum += $3} END {print sum}' rows.tmp)"
    parked_count="$(mawk -F ',' '{sum += $4} END {print sum}' rows.tmp)"
    excluded_count="$(( white_count + dead_count + parked_count ))"

    printf "%s" "$(( excluded_count * 100 / raw_count ))"
}

# Entry point

trap 'find . -maxdepth 1 -type f -name "*.tmp" -delete' EXIT

# Install csvkit
command -v csvgrep &> /dev/null || pip install -q csvkit

$FUNCTION --format-all

update_readme

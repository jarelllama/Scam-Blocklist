#!/bin/bash

# Update the README.md content and statistics.

update_readme() {
    cat << EOF > README.md
# Jarelllama's Scam Blocklist

${BLOCKLIST_DESCRIPTION}

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

\`\`\` text
Total domains: $(grep -cF '||' lists/adblock/scams.txt)
Light version: $(grep -cF '||' lists/adblock/scams_light.txt)

New domains after filtering:
Today | Monthly | %Monthly | %Filtered | Source
$(print_stats)

- %Monthly: percentage out of total domains from all sources.
- %Filtered: percentage of dead, whitelisted, and parked domains.

Dead domains removed today: $(mawk -F ',' '{ sum += $3 } END { print sum }' <<< "$(mawk "/${TODAY},dead_count/" "$DOMAIN_LOG")")
Dead domains removed this month: $(mawk -F ',' '{ sum += $3 } END { print sum }' <<< "$(mawk "/${THIS_MONTH},dead_count/" "$DOMAIN_LOG")")
Resurrected domains added today: $(mawk -F ',' '{ sum += $3 } END { print sum }' <<< "$(mawk "/${TODAY},resurrected_count/" "$DOMAIN_LOG")")

Parked domains removed this month: $(mawk -F ',' '{ sum += $3 } END { print sum }' <<< "$(mawk "/${THIS_MONTH},parked_count/" "$DOMAIN_LOG")")
Unparked domains added today: $(mawk -F ',' '{ sum += $3 } END { print sum }' <<< "$(mawk "/${TODAY},unparked_count/" "$DOMAIN_LOG")")
\`\`\`

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
Total domains: $(grep -cF '||' lists/adblock/nsfw.txt)
<br>
<br>
This blocklist does not just include adult videos, but also NSFW content of the artistic variety (rule34, illustrations, etc).
</details>

### Parked domains

For list maintainers interested in using the parked domains as a source, the list of parked domains can be found here: [parked_domains.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/data/parked_domains.txt). This list is capped at 75,000 domains.

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
EOF
}

readonly FUNCTION='bash scripts/tools.sh'
readonly DOMAIN_LOG='config/domain_log.csv'
readonly SOURCES='config/sources.csv'
readonly SOURCE_LOG='config/source_log.csv'
TODAY="$(TZ=Asia/Singapore date +"%d-%m-%y")"
THIS_MONTH="$(TZ=Asia/Singapore date +"%m-%y")"
readonly TODAY THIS_MONTH

# Return the statistics for all enabled sources.
print_stats() {
    local this_month total_this_month
    total_this_month="$(sum "$THIS_MONTH" all)"

    while read -r source; do
        this_month="$(sum "$THIS_MONTH")"

        printf "%5s |%8s |%7s %% |%8s %% | %s" \
        "$(sum "$TODAY")" "$this_month" \
        "$(( this_month * 100 / total_this_month ))" \
        "$(sum_excluded)" "$source"
    done <<< "$(mawk -F ',' '$4 == "y" { print $1 }' "$SOURCES")"

    this_month="$(sum "$THIS_MONTH" all)"

    printf "%5s |%8s |%7s %% |%8s %% | All sources" \
        "$(sum "$TODAY" all)" "$this_month" \
        "$(( this_month * 100 / total_this_month ))" \
        "$(sum_excluded all)"
}

# Note that csvcut is used in the following functions as the Google Search
# search terms may contain commas which makes using mawk complicated.

# Function 'sum' is an echo wrapper that returns the total sum of filtered
# domains retrieved by the given source for that timeframe.
# Input:
#   $1: timeframe to process
#   $2: either 'all' for all sources, or empty for "$source"
sum() {
    # Print dash if no runs for that timeframe found
    if ! grep -qF "$1" "$SOURCE_LOG"; then
        printf "-"
        return
    fi

    if [[ "$1" == 'all' ]]; then
        source=''
    fi

    mawk "/${1},${source}.*,saved$/" "$SOURCE_LOG" | csvcut -c 5 \
        | mawk '{ sum += $1 } END { print sum }'
}

# Function 'sum_excluded' is an echo wrapper that returns the percentage of
# excluded domains out of the raw count retrieved by the given source.
# Input:
#   $2: either 'all' for all sources, or empty for "$source"
sum_excluded() {
    if [[ "$1" == 'all' ]]; then
        source=''
    fi

    read -r raw_count excluded_count \
        <<< "$(mawk -v source="$source" -F ',' '$2 == source { print }' \
        "$SOURCE_LOG" | csvcut -c 4,6,7,8 | mawk -F ',' '
        {
            raw_count += $1
            white_count += $2
            dead_count += $3
            parked_count += $4
        }
        END {
            print raw_count, white_count + dead_count + parked_count
        }
        ')"

    if (( raw_count == 0 )); then
        printf 0
    else
        printf "%s" "$(( excluded_count * 100 / raw_count ))"
    fi
}

# Entry point

set -e

trap 'rm ./*.tmp temp 2> /dev/null || true' EXIT

# Install csvkit
command -v csvgrep &> /dev/null || pip install -q csvkit

$FUNCTION --format-files

update_readme

#!/bin/bash
raw_file='data/raw.txt'
search_log='data/search_log.csv'
domain_log='data/domain_log.csv'
todays_date="$(TZ=Asia/Singapore date +"%d-%m-%y")"
yesterdays_date="$(TZ=Asia/Singapore date -d "yesterday" +"%d-%m-%y")"

function main {
    command -v csvstat &> /dev/null || pip install -q csvkit
    format_list "$raw_file"
    format_list "$search_log"
    format_list "$domain_log"
    build_adblock
    build_dnsmasq
    build_unbound
    build_wildcard_asterisk
    build_wildcard_domains
    update_readme
}

function update_readme {
    total_count=$(wc -w < "$raw_file")
    total_count_today=$(count_for_day "$todays_date")
    total_count_yesterday=$(count_for_day "$yesterdays_date")
    # Find 5 most recently added domains
    new_domains=$(csvgrep -c 2 -m "new_domain" "$domain_log" | csvcut -c 3 | tail +2 | tail -5)

    cat << EOF > README.md
# Jarelllama's Scam Blocklist

Blocklist for scam sites automatically retrieved from Google Search, updated daily. Also includes malicious hosting sites.

| Format | Syntax |
| --- | --- |
| [Adblock Plus](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/adblock/scams.txt) | \|\|scam.com^ |
| [Dnsmasq](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/dnsmasq/scams.txt) | local=/scam.com/ |
| [Unbound](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/unbound/scams.txt) | local-zone: "scam.com." always_nxdomain |
| [Wildcard Asterisk](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_asterisk/scams.txt) | \*.scam.com |
| [Wildcard Domains](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/lists/wildcard_domains/scams.txt) | scam.com |

## Stats

\`\`\`
Total domains: $total_count

Domains found today: $total_count_today
Domains found yesterday: $total_count_yesterday

The 5 most recently added domains:
$new_domains
\`\`\`

## How domains are added to the blocklist

- The domain retrieval process searches Google with a list of search terms almost exclusively used in scam sites. These search terms are manually added while investigating sites on r/Scams. See the list of search terms here: [search_terms.csv](https://github.com/jarelllama/Scam-Blocklist/blob/main/config/search_terms.csv)
- The domains from the search results are filtered against a whitelist (scam reporting sites, forums, vetted companies, etc.), along with other filtering
- The domains are checked against the [Tranco 1M Toplist](https://tranco-list.eu/) and flagged domains are vetted manually
- Redundant entries are removed via wildcard matching. For example, 'sub.spam.com' is a wildcard match of 'spam.com' and is, therefore, redundant and is removed. Many of these wildcard domains also happen to be malicious hosting sites

The full domain retrieval and filtering process can be viewed in the repository's code.

The domain retrieval process runs daily at 16:30 UTC.

## Why the Hosts format is not supported

Malicious domains often have [wildcard DNS records](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/) that allow scammers to create large amounts of subdomain records. These subdomains are often random strings such as 'longrandomstring.scam.com'. To collate individual subdomains would be a difficult task and would inflate the blocklist size. Therefore, only formats supporting wildcard matching are built.

## Malicious hosting sites

Wildcard domains are added manually to the blocklist to reduce the number of entries via wildcard matching. Many of these wildcard domains are discovered to be malicious hosting sites with multiple subdomains pointing to scam sites. These malicious hosting sites are included in the blocklist and can be found among the wildcard domains in [wildcards.txt](https://github.com/jarelllama/Scam-Blocklist/blob/main/data/wildcards.txt).

## Dead domains

Dead domains are removed daily using [AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter). Note that domains acting as wildcards are excluded from this process.

## See also

[Hagezi's DNS Blocklists](https://github.com/hagezi/dns-blocklists) (uses this blocklist as a source)

[Durablenapkin's Scam Blocklist](https://github.com/durablenapkin/scamblocklist)

[Elliotwutingfeng's Global Anti-Scam Organization Blocklist](https://github.com/elliotwutingfeng/GlobalAntiScamOrg-blocklist)

[Elliotwutingfeng's Inversion DNSBL Blocklist](https://github.com/elliotwutingfeng/Inversion-DNSBL-Blocklists)

[r/Scams Subreddit](https://www.reddit.com/r/Scams)

## Resources

[ShellCheck](https://github.com/koalaman/shellcheck): shell script static analysis tool

[LinuxCommand's Coding Standards](https://linuxcommand.org/lc3_adv_standards.php): shell script coding standard

[Hagezi's DNS Blocklist](https://github.com/hagezi/dns-blocklists): inspiration and reference

[Google's Custom Search JSON API](https://developers.google.com/custom-search/v1/introduction): Google Search API

[Tranco Toplist](https://tranco-list.eu/): list of the 1 million top ranked domains

[AdGuard's Dead Domains Linter](https://github.com/AdguardTeam/DeadDomainsLinter): tool for checking AdBlock rules for dead domains

## Appreciation

Thanks to the following people for the help, inspiration and support!

[@hagezi](https://github.com/hagezi)

[@iam-py-test](https://github.com/iam-py-test)

[@bongochong](https://github.com/bongochong)
EOF
}

function count_for_day {
    runs=$(csvgrep -c 1 -r "$1" "$search_log" | csvcut -c 4 | tail +2)  # Find all runs on that particular day
    total_count=0  # Initiaize total count
    for count in $runs; do
        total_count=$((total_count + count))  # Calculate sum of domains retrieved that day
    done
    printf "%s" "$total_count"  # Return domain count to function caller
}

function build_list {
    blocklist_path="lists/${directory}/scams.txt"
    [[ -d "$(dirname $blocklist_path)" ]] || mkdir "$(dirname $blocklist_path)"  # Create directory if not present

    # Format domains for each syntax type
    formatted_domains=$(awk -v before="$4" -v after="$5" '{print before $0 after}' "$raw_file" | sort -u)
    total_count=$(wc -l <<< "$formatted_domains")  # Count total of formatted domains

    cat << EOF > "$blocklist_path"  # Append header onto blocklist
${3} Title: Jarelllama's Scam Blocklist
${3} Description: Blocklist for scam sites automatically retrieved from Google Search, updated daily. Also includes malicious hosting sites.
${3} Homepage: https://github.com/jarelllama/Scam-Blocklist
${3} License: GNU GPLv3 (https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md)
${3} Version: $(date -u +"%m.%d.%H%M%S.%Y")
${3} Last modified: $(date -u)
${3} Syntax: ${1}
${3} Total number of entries: ${total_count}
${3}
EOF

    [[ "$syntax" == 'Unbound' ]] && printf "server:\n" >> "$blocklist_path"  # Special case for Unbound syntax
    printf "%s\n" "$formatted_domains" >> "$blocklist_path"  # Append formatted domains onto blocklist
}

function format_list {
    [[ -f "$1" ]] || return  # Return if file does not exist
    # If file is a CSV file, do not sort
    if [[ "$1" == *.csv ]]; then
        sed -i 's/\r$//' "$1"  
        return
    fi
    # Format carriage return characters, remove empty lines, sort and remove duplicates
    tr -d '\r' < "$1" | sed '/^$/d' | sort -u > "${1}.tmp" && mv "${1}.tmp" "$1"
}

function build_adblock {
    syntax='Adblock Plus'
    directory="adblock"
    comment='!'
    before='||'
    after='^'
    build_list "$syntax" "$directory" "$comment" "$before" "$after"
}

function build_dnsmasq {
    syntax='Dnsmasq' 
    directory="dnsmasq"
    comment='#'
    before='local=/'
    after='/'
    build_list "$syntax" "$directory" "$comment" "$before" "$after"
}

function build_unbound {
    syntax='Unbound' 
    directory="unbound"
    comment='#'
    before='local-zone: "'
    after='." always_nxdomain'
    build_list "$syntax" "$directory" "$comment" "$before" "$after"
}

function build_wildcard_asterisk {
    syntax='Wildcard Asterisk'
    directory="wildcard_asterisk"
    comment='#'
    before='*.'
    after=''
    build_list "$syntax" "$directory" "$comment" "$before" "$after"
}

function build_wildcard_domains {
    syntax='Wildcard Domains'
    directory="wildcard_domains"
    comment='#'
    before=''
    after=''
    build_list "$syntax" "$directory" "$comment" "$before" "$after"
}

main

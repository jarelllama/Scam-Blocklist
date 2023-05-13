# Scam Blocklist

[![Build](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/build.yml/badge.svg)](https://github.com/jarelllama/Scam-Blocklist/actions/workflows/build.yml)

### Stats

```
Unique scam sites found:
Today: todays_count
Yesterday: yest_count
Manually: manual_count
Automatically: auto_count
Total: total_count (since May 10 2023)

Updated: update_time
```

### How domains are added to the blocklist

- The retrieval script searches Google with a list of search terms almost exclusively used in scam sites. See the list of search terms here: [search_terms.txt](https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/search_terms.txt)
- Domains are filtered against a whitelist (scam reporting sites, forums, genuine stores, etc.), along with other filtering
- Domains found in the Cisco Umbrella 1M toplist are checked manually (checked during retrieval and toplist updates)
- Domains in the Adblock Plus list with the same second-level domain are compressed into one rule to remove redundant entries

Malicious domains found in [r/Scams](https://www.reddit.com/r/Scams) are occasionally added after being manually vetted.

Domains are retrieved from multiple regions such as Asia, Europe, and North America.

To see the full filtering and retrieval process check out the code in the repository.

### Dead domains

Domains returning `NXDOMAIN` are removed during the domain retrieval process and once a day for the full blocklist. Dead domains that resolve again are added back.

### Inspiration

After browsing r/Scams for weeks and manually reporting scam sites to Hagezi's issue tracker, I realized most scam sites follow a similar template.

Although I could never keep up with the number of scam sites created daily, I aim to retrieve as many new scam sites as possible with this project.

### Limitations

Most of the domains retrieved are from manually running the script on my phone's terminal emulator. After successive manual runs, I have to change VPN servers to overcome Google's IP blocking.

The number of domains retrieved in a day varies depending on my interest and free time. However, if left unattended, the blocklist is still capable of automatic daily updates but at a much lower retrieval count than if I were to manually run the script.

See [stats](https://github.com/jarelllama/Scam-Blocklist#stats) for the number of unique domains retrieved from manual and automatic runs.

### See also

[Durablenapkin's Scam Blocklist](https://github.com/durablenapkin/scamblocklist)

[Hagezi's Fake list](https://github.com/hagezi/dns-blocklists#fake) (uses my list as a source)

[Elliotwutingfeng's Global Anti Scam Organization blocklist](https://github.com/elliotwutingfeng/GlobalAntiScamOrg-blocklist)

[Reddit's r/Scams subreddit](https://www.reddit.com/r/Scams)

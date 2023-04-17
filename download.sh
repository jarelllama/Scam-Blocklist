#!/bin/bash

# Download required files

read -p "Download the toplist.txt? (y/N): " answer

if [[ "$answer" == "y" ]]; then
  wget -N https://raw.githubusercontent.com/hagezi/dns-data-collection/main/top/toplist.txt
fi

wget -N https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/update.sh

wget -N https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/blacklist.txt

wget -N https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/whitelist.txt

wget -N https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/white_tlds.txt

wget -N https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/search_terms.txt

wget -N https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/edit.sh

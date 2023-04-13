#!/bin/bash

# Download required files

read -p "Do you want to download the toplist.txt? (y/N)" choice

if [ "$choice" =~ ^[yY]$ ]; then
wget -N https://raw.githubusercontent.com/hagezi/dns-data-collection/main/top/toplist.txt
fi

wget -N https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/domains.sh

wget -N https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/list.sh

wget -N https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/blacklist.txt

wget -N https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/whitelist.txt

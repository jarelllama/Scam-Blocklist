#!/bin/bash

domains_file="domains"
blacklist_file="blacklist.txt"
toplist_file="toplist.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

wget -q https://raw.githubusercontent.com/hagezi/dns-data-collection/main/top/toplist.txt -O "$toplist_file"

git config user.email "$github_email"
git config user.name "$github_name"

git add "$toplist_file"
git commit -mq "Update $toplist_file"
git push -q

grep -xFf "$domains_file" "$toplist_file" | grep -vxFf "$blacklist_file" > tmp1.txt

if ! [[ -s tmp1.txt ]]; then
    rm tmp*.txt
    exit 0
fi

echo -e "\nDomains in toplist:"
cat tmp1.txt

rm tmp*.txt

exit 1

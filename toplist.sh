#!/bin/bash

toplist_file="toplist.txt"

wget -N https://raw.githubusercontent.com/hagezi/dns-data-collection/main/top/toplist.txt -O "$toplist_file"

git add "$toplist_file"
git commit -m "Update toplist.txt"
git push

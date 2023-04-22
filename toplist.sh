#!/bin/bash

wget -N https://raw.githubusercontent.com/hagezi/dns-data-collection/main/top/toplist.txt

git add toplist.txt
git commit -m "Update toplist.txt"
git push

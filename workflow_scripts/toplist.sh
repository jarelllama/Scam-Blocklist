#!/bin/bash

toplist_file="toplist.txt"
email="91372088+jarelllama@users.noreply.github.com"
name="jarelllama"

wget https://raw.githubusercontent.com/hagezi/dns-data-collection/main/top/toplist.txt -O "$toplist_file"

git config user.email "$email"
git config user.name "$name"

git add "$toplist_file"
git commit -m "Update $toplist_file"
git push

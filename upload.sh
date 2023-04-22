#!/bin/bash

domains_file="domains"

sed -i "s/Current number of domains: .*/Current number of domains: $(wc -l < "$domains_file")/" README.md

git add domains README.md
git commit -m "Update domains"
git push

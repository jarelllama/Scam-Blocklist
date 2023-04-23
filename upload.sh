#!/bin/bash

domains_file="domains"
num_domains=$(grep -vE '^(#|$)' "$domains_file" | wc -l)

sed -i "s/Current number of domains: .*/Current number of domains: \`$num_domains\`/" README.md

git add "$domains_file" README.md
git commit -m "Update domains"
git push

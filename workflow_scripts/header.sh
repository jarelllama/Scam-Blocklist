#!/bin/bash

domains_file="domains"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

grep -vE '^(#|$)' "$domains_file" > tmp1.txt

num_domains=$(wc -l < tmp1.txt)

echo "# Title: Jarelllama's Scam Blocklist
# Description: Blocklist for scam sites extracted from Google
# Homepage: https://github.com/jarelllama/Scam-Blocklist
# Source: https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/domains
# License: GNU GPLv3 (https://www.gnu.org/licenses/gpl-3.0.en.html)
# Last modified: $(date -u)
# Total number of domains: $num_domains
" | cat - tmp1.txt > "$domains_file"

sed -i "s/Current number of domains: .*/Current number of domains: \`$num_domains\`/" README.md

rm tmp*.txt

git config user.email "$github_email"
git config user.name "$github_name"

git add "$domains_file" README.md
git commit -m "Update domains count"
git push

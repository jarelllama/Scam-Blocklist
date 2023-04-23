#!/bin/bash

domains_file="domains"
email="91372088+jarelllama@users.noreply.github.com"
name="jarelllama"

function update_header {
    num_domains=$(wc -l < "$domains_file")

    echo "# Title: Jarelllama's Scam Blocklist
# Description: Blocklist for scam sites extracted from Google
# Homepage: https://github.com/jarelllama/Scam-Blocklist
# Source: https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/domains
# License: GNU GPLv3 (https://www.gnu.org/licenses/gpl-3.0.en.html)
# Last modified: $(date -u)
# Total number of domains: $num_domains
" | cat - "$domains_file" > tmp1.txt

    mv tmp1.txt "$domains_file"
}

grep -vE '^(#|$)' "$domains_file" > tmp1.txt

touch tmp_dead.txt

cat tmp1.txt | xargs -I{} -P8 bash -c "
  if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
      echo {} >> tmp_dead.txt
      echo '{} (dead)'
  fi
"

comm -23 tmp1.txt <(sort tmp_dead.txt) > "$domains_file"

echo -e "\nTotal domains removed: $(wc -l < tmp_dead.txt)\n"

update_header

rm tmp*.txt

git config user.email "$email"

git config user.name "$name"

git add "$domains_file"

git commit -m "Remove dead domains"

git push

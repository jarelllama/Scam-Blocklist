#!/bin/bash

domains_file="domains"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="toplist.txt"

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

cp "$domains_file" "$domains_file.bak"

grep -vE '^(#|$)' "$domains_file" > tmp1.txt

awk NF tmp1.txt > tmp2.txt

tr '[:upper:]' '[:lower:]' < tmp2.txt > tmp3.txt

num_before=$(wc -l < tmp3.txt)

sort -u tmp3.txt -o tmp4.txt

echo "Domains removed:"

grep -Ff "$whitelist_file" tmp4.txt | grep -vxFf "$blacklist_file" | awk '{print $0 " (whitelisted)"}'

grep -Ff "$whitelist_file" tmp4.txt | grep -vxFf "$blacklist_file" > tmp_whitelisted.txt

comm -23 tmp4.txt <(sort tmp_whitelisted.txt) > tmp5.txt

grep -E '\.(edu|gov)$' tmp5.txt | awk '{print $0 " (TLD)"}'

grep -vE '\.(edu|gov)$' tmp5.txt > tmp6.txt

grep -vE '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' tmp6.txt | awk '{print $0 " (invalid)"}'
    
grep -E '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' tmp6.txt > tmp7.txt

touch tmp_dead.txt

cat tmp7.txt | xargs -I{} -P8 bash -c "
  if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
      echo {} >> tmp_dead.txt
      echo '{} (dead)'
  fi
"

comm -23 tmp7.txt <(sort tmp_dead.txt) > tmp8.txt

mv tmp8.txt "$domains_file"

echo -e "\nDomains in toplist:"
grep -xFf "$domains_file" "$toplist_file" | grep -vxFf "$blacklist_file"

num_after=$(wc -l < "$domains_file")

echo "Total domains before: $num_before"
echo "Total domains removed: $((num_before - num_after))"
echo "Final domains after: $num_after"

update_header

rm tmp*.txt

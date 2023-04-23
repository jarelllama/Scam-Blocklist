#!/bin/bash

domains_file="domains"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="toplist.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

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

mv tmp7.txt "$domains_file"

echo -e "\nDomains in toplist:"
grep -xFf "$domains_file" "$toplist_file" | grep -vxFf "$blacklist_file"

num_after=$(wc -l < "$domains_file")

echo "Total domains before: $num_before"
echo "Total domains removed: $((num_before - num_after))"
echo "Final domains after: $num_after"

rm tmp*.txt

read -p "Do you want to push any changes? (y/N): " answer
if [[ "$answer" != "y" ]]; then
    exit 0
fi

echo ""

git config user.email "$github_email"
git config user.name "$github_name"

git add "$domains_file"
git commit -m "Update domains"
git push

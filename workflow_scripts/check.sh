#!/bin/bash

domains_file="domains"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

grep -vE '^(#|$)' "$domains_file" > tmp1.txt

error=0

if grep -q '^[[:space:]]*$' tmp1.txt; then
    echo -e "\nThe blocklist contains empty lines."
    error=1
fi

awk NF tmp1.txt > tmp2.txt

if grep -q '[A-Z]' tmp2.txt; then
    echo -e "\nThe blocklist contains capitalized letters."
    error=1
fi

tr '[:upper:]' '[:lower:]' < tmp2.txt > tmp3.txt

num_before=$(wc -l < tmp3.txt)

echo "Domains removed:"

awk 'seen[$0]++ == 1 {print $0 " (duplicate)"}' tmp3.txt

sort -u tmp3.txt -o tmp4.txt

grep -E '\.(edu|gov)$' tmp4.txt | awk '{print $0 " (TLD)"}'

grep -vE '\.(edu|gov)$' tmp4.txt > tmp5.txt

grep -vE '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' tmp5.txt | awk '{print $0 " (invalid)"}'
    
grep -E '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' tmp5.txt > tmp6.txt

mv tmp6.txt "$domains_file"

num_after=$(wc -l < "$domains_file")

if [[ "$num_before" != "$num_after" ]]; then
    error=1
fi

rm tmp*.txt

if [[ error == 0 ]]; then
    exit 0
fi

echo -e "\nTotal domains before: $num_before"
echo "Total domains removed: $((num_before - num_after))"
echo "Final domains after: $num_after"

git config user.email "$github_email"
git config user.name "$github_name"

git add "$domains_file"
git commit -mq "Update domains"
git push -q

exit 1

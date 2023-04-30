#!/bin/bash

raw_file="data/raw.txt"
subdomains_file="data/subdomains.txt"
github_email='91372088+jarelllama@users.noreply.github.com'
github_name='jarelllama'

git config user.email "$github_email"
git config user.name "$github_name"

sort "$subdomains_file" -o "$subdomains_file"

while read -r subdomain; do
    grep "^$subdomain\." "$raw_file" >> subdomains.tmp
done < "$subdomains_file"

comm -23 "$raw_file" "$subdomains_file" > base_domains.tmp

touch subdomains_alive.tmp

while read -r subdomain; do
    awk -v subdomain="$subdomain" '{print subdomain"."$0}' base_domains.tmp > subdomains.tmp

    comm -23 subdomains.tmp "$raw_file" > unique_subdomains.tmp

    cat unique_subdomains.tmp | xargs -I{} -P8 bash -c "
        if ! dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> subdomains_alive.tmp
        fi
    "
done < "$subdomains_file"

cat subdomains_alive.tmp "$raw_file" > raw.tmp

sort -u raw.tmp -o raw.tmp

comm -23 raw.tmp "$raw_file" > new_entries.tmp

if ! [[ -s new_entries.tmp ]]; then
    echo -e "\nNo domains added.\n"
    rm *.tmp
    exit 0
fi

cp raw.tmp "$raw_file"

echo -e "\nDomains added:"
cat new_entries.tmp

echo -e "\nTotal domains added: $(wc -l < unique.tmp)\n"

rm *.tmp

git add "$raw_file" "$subdomains_file"
git commit -qm "Add subdomains"
git push -q

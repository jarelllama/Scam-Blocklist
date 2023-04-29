#!/bin/bash

raw_file="data/raw.txt"
subdomains_file="data/subdomains.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

grep '^www\.' "$raw_file" > www.tmp

awk '{sub(/^www\./, ""); print}' www.tmp > base_domains.tmp

touch base_domains_alive.tmp

cat base_domains.tmp | xargs -I{} -P8 bash -c "
    if ! dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
        echo {} >> base_domains_alive.tmp
    fi
"

cat base_domains_alive.tmp "$raw_file" > raw.tmp

grep -v '^www\.' raw.tmp > base_domains_only.tmp

touch subdomains_alive.tmp

while read -r subdomain; do
    awk -v subdomain="$subdomain" '{print subdomain"."$0}' base_domains_only.tmp > with_subdomain.tmp

    cat with_subdomain.tmp | xargs -I{} -P8 bash -c "
        if ! dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> subdomains_alive.tmp
        fi
    "
done < "$subdomains_file"

cat subdomains_alive.tmp >> raw.tmp

sort raw.tmp -o raw.tmp

comm -23 raw.tmp "$raw_file" > unique.tmp

if ! [[ -s unique.tmp ]]; then
    echo -e "\nNo domains added.\n"
    rm *.tmp
    exit 0
fi

cp raw.tmp "$raw_file"

echo -e "\nDomains added:"
cat unique.tmp

echo -e "\nTotal domains added: $(wc -l < unique.tmp)\n"

rm *.tmp

git config user.email "$github_email"
git config user.name "$github_name"

git add "$raw_file"
git commit -qm "Add subdomains"
git push -q

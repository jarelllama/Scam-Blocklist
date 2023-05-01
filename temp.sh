#!/bin/bash

raw_file="data/raw.txt"
subdomains_file="data/subdomains.txt"
github_email='91372088+jarelllama@users.noreply.github.com'
github_name='jarelllama'

while read -r subdomain; do
    grep "^$subdomain\." "$raw_file" >> subdomains.tmp
done < "$subdomains_file"

# Process only second-level domains
comm -23 "$raw_file" subdomains.tmp > domains.tmp

random_subdomain='6nd7p7ccay6r5da'

awk -v subdomain="$random_subdomain" '{print subdomain"."$0}' domains.tmp > random_subdomain.tmp

touch wildcards.tmp

# Find domains with a wildcard record (domains that resolve any subdomain)
cat random_subdomain.tmp | xargs -I{} -P8 bash -c "
    if ! dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
        echo {} >> wildcards.tmp
    fi
"

awk -v subdomain="$random_subdomain" '{sub("^"subdomain"\\.", ""); print}' wildcards.tmp > stripped_wildcards.tmp

grep -Ff stripped_wildcards.tmp "$raw_file" > wildcards.tmp

grep "^shop\." wildcards.tmp >> toremove.tmp

grep "^store\." wildcards.tmp >> toremove.tmp

sort toremove.tmp -o toremove.tmp

cat toremove.tmp

comm -23 "$raw_file" toremove.tmp > 1.tmp

mv 1.tmp "$raw_file"

rm *.tmp

git add "$raw_file"
git commit -qm "Remove subdomains from wildcard domains"
git push -q

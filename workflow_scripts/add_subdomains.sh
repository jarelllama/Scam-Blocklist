#!/bin/bash

raw_file="data/raw.txt"
subdomains_file="data/subdomains.txt"
dead_domains_file="data/dead_domains.txt"
github_email='91372088+jarelllama@users.noreply.github.com'
github_name='jarelllama'

git config user.email "$github_email"
git config user.name "$github_name"

while read -r subdomain; do
    grep "^$subdomain\." "$raw_file" >> subdomains.tmp
done < "$subdomains_file"

comm -23 "$raw_file" subdomains.tmp > base_domains.tmp

random_subdomain='6nd7p7ccay6r5da'

# Append a random subdomain
awk -v subdomain="$random_subdomain" '{print subdomain"."$0}' base_domains.tmp > random_subdomain.tmp

touch wildcards.tmp

# Find wildcard domains (domains that resolve any subdomain)
cat random_subdomain.tmp | xargs -I{} -P8 bash -c "
    if ! dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
        echo {} >> wildcards.tmp
    fi
"

# Strip the wildcards to their base domains
awk -v subdomain="$random_subdomain" '{sub("^"subdomain"\\.", ""); print}' wildcards.tmp > stripped_wildcards.tmp

mv stripped_wildcards.tmp wildcards.tmp

grep -vxFf wildcards.tmp base_domains.tmp > non_wildcards.tmp

mv non_wildcards.tmp domains.tmp

touch dead_subdomains.tmp

while read -r subdomain; do
    # Append the current subdomain to the base domains
    awk -v subdomain="$subdomain" '{print subdomain"."$0}' domains.tmp > 1.tmp

    # Remove subdomains already present in the raw file
    comm -23 1.tmp "$raw_file" > 2.tmp

    # Remove known dead subdomains
    comm -23 2.tmp "$dead_domains_file" > subdomains.tmp

    cat subdomains.tmp | xargs -I{} -P8 bash -c "
        if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> dead_subdomains.tmp
        fi
    "
    
    grep -vxFf dead_subdomains.tmp subdomains.tmp >> alive_subdomains.tmp
done < "$subdomains_file"

cat dead_subdomains.tmp >> "$dead_domains_file"

sort "$dead_domains_file" -o "$dead_domains_file"

awk '{print "www."$0}' wildcards.tmp > www_wildcards.tmp

grep -vxFf "$raw_file" www_wildcards.tmp > new_wildcards.tmp

cat new_wildcards.tmp alive_subdomains.tmp > new_subdomains.tmp

if [[ -s new_subdomains.tmp ]]; then
    cat new_subdomains.tmp >> "$raw_file"

    sort "$raw_file" -o "$raw_file"

    echo -e "\nDomains added:"
cat new_subdomains.tmp

    echo -e "\nTotal domains added: $(wc -l < new_subdomains.tmp)\n"
else
    echo -e "\nNo domains added.\n"
fi

rm *.tmp

git add "$raw_file" "$dead_domains_file"
git commit -qm "Add subdomains"
git push -q

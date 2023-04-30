#!/bin/bash

raw_file="data/raw.txt"
subdomains_file="data/subdomains.txt"
dead_domains_file="data/dead_domains.txt"
github_email='91372088+jarelllama@users.noreply.github.com'
github_name='jarelllama'

git config user.email "$github_email"
git config user.name "$github_name"

# Find subdomains and append them to a file
while read -r subdomain; do
    grep "^$subdomain\." "$raw_file" >> subdomains.tmp
done < "$subdomains_file"

# Remove subdomains to get only base domains
comm -23 "$raw_file" subdomains.tmp > base_domains.tmp

touch subdomains_dead.tmp

while read -r subdomain; do
    # Append the current subdomain to the base domains
    awk -v subdomain="$subdomain" '{print subdomain"."$0}' base_domains.tmp > 1.tmp

    # Remove subdomains already in the raw file
    comm -23 1.tmp "$raw_file" > 2.tmp

    # Remove known dead subdomains
    comm -23 2.tmp "$dead_domains_file" > subdomains.tmp

    cat subdomains.tmp | xargs -I{} -P8 bash -c "
        if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> subdomains_dead.tmp
        fi
    "
    
    grep -vxFf subdomains_dead.tmp subdomains.tmp >> subdomains_alive.tmp
done < "$subdomains_file"

cat subdomains_dead.tmp >> "$dead_domains_file"

sort "$dead_domains_file" -o "$dead_domains_file"

if [[ -s subdomains_alive.tmp ]]; then
    cat subdomains_alive.tmp >> "$raw_file"

    sort "$raw_file" -o "$raw_file"

    echo -e "\nDomains added:"
cat subdomains_alive.tmp

    echo -e "\nTotal domains added: $(wc -l < subdomains_alive.tmp)\n"
else
    echo -e "\nNo domains added.\n"
fi

rm *.tmp

git add "$raw_file" "$dead_domains_file"
git commit -qm "Add subdomains"
git push -q

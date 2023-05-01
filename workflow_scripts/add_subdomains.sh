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

# Process only second-level domains
comm -23 "$raw_file" subdomains.tmp > second_level.tmp

random_subdomain='6nd7p7ccay6r5da'

awk -v subdomain="$random_subdomain" '{print subdomain"."$0}' second_level.tmp > random_subdomain.tmp

touch wildcards.tmp

# Find domains with a wildcard record (domains that resolve any subdomain)
cat random_subdomain.tmp | xargs -I{} -P8 bash -c "
    if ! dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
        echo {} >> wildcards.tmp
    fi
"

awk -v subdomain="$random_subdomain" '{sub("^"subdomain"\\.", ""); print}' wildcards.tmp > wildcards_second_level.tmp

mv wildcards_second_level.tmp wildcards.tmp

# Don't bother checking domains with wildcard records for resolving subdomains 
grep -vxFf wildcards.tmp second_level.tmp > domains.tmp

touch dead_subdomains.tmp

while read -r subdomain; do
    # Append the current subdomain in the loop to the domains
    awk -v subdomain="$subdomain" '{print subdomain"."$0}' domains.tmp > 1.tmp

    # Remove subdomains already present in the raw file
    comm -23 1.tmp "$raw_file" > 2.tmp

    # Remove known dead subdomains
    comm -23 2.tmp "$dead_domains_file" > 3.tmp

    cat 3.tmp | xargs -I{} -P8 bash -c "
        if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> dead_subdomains.tmp
        fi
    "
    
    grep -vxFf dead_subdomains.tmp 3.tmp >> new_subdomains.tmp
done < "$subdomains_file"

cat dead_subdomains.tmp >> "$dead_domains_file"

sort "$dead_domains_file" -o "$dead_domains_file"

awk '{print "www."$0}' wildcards.tmp > wildcards_with_www.tmp

grep -vxFf "$raw_file" wildcards_with_www.tmp > new_wildcards.tmp

cat new_wildcards.tmp new_subdomains.tmp > new_domains.tmp

if [[ -s new_domains.tmp ]]; then
    cat new_domains.tmp >> "$raw_file"

    sort "$raw_file" -o "$raw_file"

    echo -e "\nDomains added:"
    cat new_domains.tmp

    echo -e "\nTotal domains added: $(wc -l < new_domains.tmp)\n"
else
    echo -e "\nNo domains added.\n"
fi

rm *.tmp

git add "$raw_file" "$dead_domains_file"
git commit -qm "Add subdomains"
git push -q

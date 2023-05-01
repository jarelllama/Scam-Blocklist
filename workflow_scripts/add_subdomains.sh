#!/bin/bash

raw_file="data/raw.txt"
subdomains_file="data/subdomains.txt"
dead_domains_file="data/dead_domains.txt"
toplist_file="data/subdomains_toplist.txt"
github_email='91372088+jarelllama@users.noreply.github.com'
github_name='jarelllama'

git config user.email "$github_email"
git config user.name "$github_name"

while read -r subdomain; do
    grep "^$subdomain\." "$raw_file" >> subdomains.tmp
done < "$subdomains_file"

# Process only second-level domains
comm -23 "$raw_file" subdomains.tmp > domains.tmp

touch toplist_subdomains.tmp

# Find subdomains in the subdomains toplist
while read -r domain; do
    grep "\.$domain$" "$toplist_file" >> toplist_subdomains.tmp
done < domains.tmp

grep -vxFf "$raw_file" toplist_subdomains.tmp > unique_toplist_subdomains.tmp

touch alive_toplist_subdomains.tmp

cat unique_toplist_subdomains.tmp | xargs -I{} -P8 bash -c "
    if ! dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
        echo {} >> alive_toplist_subdomains.tmp
    fi
"

cat alive_toplist_subdomains.tmp >> new_domains.tmp

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

awk '{print "www."$0}' stripped_wildcards.tmp > wildcards_with_www.tmp

awk '{print "m."$0}' stripped_wildcards.tmp > wildcards_with_m.tmp

cat wildcards_with_www.tmp >> new_domains.tmp

cat wildcards_with_m.tmp >> new_domains.tmp

# Don't bother checking domains with wildcard records for resolving subdomains 
grep -vxFf stripped_wildcards.tmp domains.tmp > no_wildcards.tmp

mv no_wildcards.tmp domains.tmp

touch dead_subdomains.tmp

while read -r subdomain; do
    # Append the current subdomain in the loop to the domains
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
    
    grep -vxFf dead_subdomains.tmp subdomains.tmp >> new_subdomains.tmp
done < "$subdomains_file"

cat new_subdomains.tmp >> new_domains.tmp

cat dead_subdomains.tmp >> "$dead_domains_file"

sort "$dead_domains_file" -o "$dead_domains_file"

# Remove entries already in the raw file (new wildcard domains weren't checked earlier)
grep -vxFf "$raw_file" new_domains.tmp >  unique_domains.tmp


if [[ -s unique_domains.tmp ]]; then
    cat unique_domains.tmp >> "$raw_file"

    sort "$raw_file" -o "$raw_file"

    echo -e "\nDomains added:"
    cat unique_domains.tmp

    echo -e "\nTotal domains added: $(wc -l < unique_domains.tmp)\n"
else
    echo -e "\nNo domains added.\n"
fi

rm *.tmp

git add "$raw_file" "$dead_domains_file"
git commit -qm "Add subdomains"
git push -q

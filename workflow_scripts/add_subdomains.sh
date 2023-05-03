#!/bin/bash

raw_file="data/raw.txt"
subdomains_file="data/subdomains.txt"
toplist_file="data/subdomains_toplist.txt"
dead_domains_file="data/dead_domains.txt"
github_email='91372088+jarelllama@users.noreply.github.com'
github_name='jarelllama'

git config user.email "$github_email"
git config user.name "$github_name"

while read -r subdomain; do
    grep "^$subdomain\." "$raw_file" >> only_subdomains.tmp
done < "$subdomains_file"

comm -23 "$raw_file" only_subdomains.tmp > second_level_domains.tmp

function add_toplist_subdomains {
    touch toplist_subdomains.tmp

    while read -r domain; do
        grep "\.$domain$" "$toplist_file" >> toplist_subdomains.tmp
    done < second_level_domains.tmp

    grep -vxFf "$raw_file" toplist_subdomains.tmp > unique_toplist_subdomains.tmp

    touch alive_toplist_subdomains.tmp
    
    cat unique_toplist_subdomains.tmp | xargs -I{} -P8 bash -c "
        if ! dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> alive_toplist_subdomains.tmp
        fi
    "

    if ! [[ -s alive_toplist_subdomains.tmp ]]; then
        return
    fi
    
    echo -e "\nSubdomains found in the toplist"
    cat alive_toplist_subdomains.tmp

    cat alive_toplist_subdomains.tmp >> new_domains.tmp
}

function add_subdomains_to_wildcards {
    random_subdomain='6nd7p7ccay6r5da'

    awk -v subdomain="$random_subdomain" '{print subdomain"."$0}' second_level_domains.tmp > random_subdomain.tmp

    touch wildcards.tmp

    # Find domains with a wildcard record (domains that resolve any subdomain)
    cat random_subdomain.tmp | xargs -I{} -P8 bash -c "
        if ! dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> wildcards.tmp
        fi
    "

    awk -v subdomain="$random_subdomain" '{sub("^"subdomain"\\.", ""); print}' wildcards.tmp > wildcard_second_level_domains.tmp

    # Create a file with no wildcard domains. This file is sorted 
    grep -vxFf wildcard_second_level_domains.tmp second_level_domains.tmp > no_wildcards.tmp

    if ! [[ -s wildcard_second_level_domains.tmp ]]; then
        return
    fi

    echo -e "\nWildcard domains found:"
    cat wildcard_second_level_domains.tmp
    echo 'The `www` and `m` subdomains will be added to these domains.'

    awk '{print "www."$0}' wildcard_second_level_domains.tmp > wildcards_with_www.tmp

    awk '{print "m."$0}' wildcard_second_level_domains.tmp > wildcards_with_m.tmp

    cat wildcards_with_www.tmp >> new_domains.tmp

    cat wildcards_with_m.tmp >> new_domains.tmp
}

function add_subdomains {
    touch dead_subdomains.tmp

    while read -r subdomain; do
        # Append the current subdomain in the loop to the domains
        awk -v subdomain="$subdomain" '{print subdomain"."$0}' no_wildcards.tmp > 1.tmp

        # Remove subdomains already present in the raw file
        comm -23 1.tmp "$raw_file" > 2.tmp

        # Remove known dead subdomains
        comm -23 2.tmp "$dead_domains_file" > 3.tmp
    
        # Remove subdomains already in the new domains file
        grep -vxFf new_domains.tmp 3.tmp > subdomains.tmp

        cat subdomains.tmp | xargs -I{} -P8 bash -c "
            if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
                echo {} >> dead_subdomains.tmp
            fi
        "

        grep -vxFf dead_subdomains.tmp subdomains.tmp > alive_subdomains.tmp

        if ! [[ -s alive_subdomains.tmp ]]; then
            continue
        fi

        echo -e "\nResolving subdomains found:"
        cat alive_subdomains.tmp

        cat alive_subdomains.tmp >> new_domains.tmp
    done < "$subdomains_file"
}

add_toplist_subdomains

add_subdomains_to_wildcards

add_subdomains

sort -u new_domains.tmp -o new_domains.tmp

# Remove entries already in the raw file
comm -23 new_domains.tmp "$raw_file" > unique_domains.tmp

if [[ -s unique_domains.tmp ]]; then
    cat unique_domains.tmp >> "$raw_file"

    sort "$raw_file" -o "$raw_file"

    echo -e "\nAll domains added:"
    cat unique_domains.tmp

    echo -e "\nTotal domains added: $(wc -l < unique_domains.tmp)\n"
else
    echo -e "\nNo domains added.\n"
fi

rm *.tmp

git add "$raw_file"
git commit -qm "Add subdomains"
git push -q

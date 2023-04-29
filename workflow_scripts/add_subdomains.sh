#!/bin/bash

raw_file="data/raw.txt"
subdomains_file="data/subdomains.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

grep '^www\.' "$raw_file" > with_www.tmp

comm -23 "$raw_file" with_www.tmp > no_www.tmp

awk '{sub(/^www\./, ""); print}' with_www.tmp > no_www_new.tmp

awk '{print "www."$0}' no_www.tmp > with_www_new.tmp

cat no_www_new.tmp with_www_new.tmp > flipped.tmp

touch flipped_alive.tmp

cat flipped.tmp | xargs -I{} -P8 bash -c "
    if ! dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
        echo {} >> flipped_alive.tmp
    fi
"

cat flipped_alive.tmp "$raw_file" > raw.tmp

grep -v '^www\.' raw.tmp > no_www.tmp

touch subdomain_alive.tmp

while read -r subdomain; do
    awk -v subdomain="$subdomain" '{print subdomain"."$0}' no_www.tmp > subdomain.tmp

    cat subdomain.tmp | xargs -I{} -P4 bash -c "
        if ! dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> subdomain_alive.tmp
        fi
    "

    cat subdomain_alive.tmp >> raw.tmp
done < "$subdomains_file"

sort raw.tmp -o raw.tmp

comm -23 raw.tmp "$raw_file" > unique.tmp

if ! [[ -s unique.tmp ]]; then
    echo -e "\nNo domains added.\n"
    rm *.tmp
    exit 0
fi

mv raw.tmp "$raw_file"

echo -e "\nDomains added:"
cat unique.tmp

echo -e "\nTotal domains added: $(wc -l < unique.tmp)\n"

rm *.tmp

git config user.email "$github_email"
git config user.name "$github_name"

git add "$raw_file"
git commit -qm "Add subdomains"
git push -q

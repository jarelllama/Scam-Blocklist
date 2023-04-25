#!/bin/bash

raw_file="data/raw.txt"

grep -vE '^(#|$)' "$raw_file" > raw.tmp

grep '^www\.' raw.tmp > with_www.tmp

comm -23 raw.tmp with_www.tmp > no_www.tmp

awk '{sub(/^www\./, ""); print}' with_www.tmp > no_www_new.tmp

awk '{print "www."$0}' no_www.tmp > with_www_new.tmp

cat no_www_new.tmp with_www_new.tmp > flipped.tmp

touch flipped_dead.tmp

cat flipped.tmp | xargs -I{} -P4 bash -c "
    if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
        echo {} >> flipped_dead.tmp
    fi
"

grep -vxFf flipped_dead.tmp flipped.tmp > flipped_alive.tmp

grep -vxFf raw.tmp flipped_alive.tmp > flipped_unique.tmp

if ! [[ -s flipped_unique.tmp ]]; then
    echo -e "\nNo domains added.\n"
    rm *.tmp
    exit 0
fi

echo -e "\nDomains added:"
cat flipped_unique.tmp

echo -e "\nTotal domains added: $(wc -l < flipped_unique.tmp)\n"

cat flipped_unique.tmp >> raw.tmp

sort raw.tmp -o "$raw_file"

rm *.tmp

git config user.email "$github_email"
git config user.name "$github_name"

git add "$raw_file"
git commit -qm "Add subdomains"
git push -q

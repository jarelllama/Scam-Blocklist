#!/bin/bash

raw_file="data/raw.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

grep '^www\.' "$raw_file" > with_www.tmp

comm -23 "$raw_file" with_www.tmp > no_www.tmp

awk '{sub(/^www\./, ""); print}' with_www.tmp > no_www_new.tmp

awk '{print "www."$0}' no_www.tmp > with_www_new.tmp

cat no_www_new.tmp with_www_new.tmp > flipped.tmp

touch flipped_dead.tmp

cat flipped.tmp | xargs -I{} -P8 bash -c "
    if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
        echo {} >> flipped_dead.tmp
    fi
"

grep -vxFf flipped_dead.tmp flipped.tmp > flipped_alive.tmp

cat flipped_alive.tmp "$raw_file" > raw.tmp

grep -v '^www\.' raw.tmp > no_www.tmp

awk '{print "m."$0}' no_www.tmp > m_subdomain.tmp

touch m_subdomain_dead.tmp

cat m_subdomain.tmp | xargs -I{} -P8 bash -c "
    if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
        echo {} >> m_subdomain_dead.tmp
    fi
"

grep -vxFf m_subdomain_dead.tmp m_subdomain.tmp > m_subdomain_alive.tmp

cat m_subdomain_alive.tmp flipped_alive.tmp > new_entries.tmp

sort new_entries.tmp -o new_entries.tmp

comm -23 new_entries.tmp "$raw_file" > new_entries_unique.tmp

if ! [[ -s new_entries_unique.tmp ]]; then
    echo -e "\nNo domains added.\n"
    rm *.tmp
    exit 0
fi

cat new_entries_unique.tmp >> "$raw_file"

sort "$raw_file" -o "$raw_file"

echo -e "\nDomains added:"
cat new_entries_unique.tmp

echo -e "\nTotal domains added: $(wc -l < new_entries_unique.tmp)\n"

rm *.tmp

git config user.email "$github_email"
git config user.name "$github_name"

git add "$raw_file"
git commit -qm "Add subdomains"
git push -q

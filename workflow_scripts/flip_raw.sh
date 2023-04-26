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

grep -vxFf "$raw_file" flipped_alive.tmp > flipped_unique.tmp

if ! [[ -s flipped_unique.tmp ]]; then
    echo -e "\nNo domains added.\n"
    rm *.tmp
    exit 0
fi

echo -e "\nDomains added:"
cat flipped_unique.tmp

echo -e "\nTotal domains added: $(wc -l < flipped_unique.tmp)\n"

cat flipped_unique.tmp >> "$raw_file"

sort "$raw_file" -o "$raw_file"

rm *.tmp

git config user.email "$github_email"
git config user.name "$github_name"

git add "$raw_file"
git commit -qm "Add subdomains"
git push -q

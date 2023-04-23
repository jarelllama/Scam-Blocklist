#!/bin/bash

domains_file="domains"

grep -vE '^(#|$)' "$domains_file" > tmp1.txt

grep '^www\.' tmp1.txt > tmp_with_www.txt

grep -vxFf tmp_with_www.txt tmp1.txt > tmp_no_www.txt

awk '{sub(/^www\./, ""); print}' tmp_with_www.txt > tmp_no_www_new.txt

awk '{print "www."$0}' tmp_no_www.txt > tmp_with_www_new.txt

cat tmp_no_www_new.txt tmp_with_www_new.txt > tmp_flipped.txt

touch tmp_flipped_dead.txt

cat tmp_flipped.txt | xargs -I{} -P4 bash -c "
    if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
        echo {} >> tmp_flipped_dead.txt
    fi
"

grep -vxFf tmp_flipped_dead.txt tmp_flipped.txt > tmp_flipped_alive.txt

if ! [[ -s tmp_flipped_alive.txt ]]; then
    rm tmp*.txt
    exit 0
fi

echo -e "\nDomains added:"
comm -23 <(sort tmp_flipped_alive.txt) tmp1.txt

echo -e "\nTotal domains added: $(comm -23 <(sort tmp_flipped_alive.txt) tmp1.txt | wc -l)"

cat tmp_flipped_alive.txt >> tmp1.txt

sort -u tmp1.txt -o "$domains_file"

rm tmp*.txt

git config user.email "$github_email"
git config user.name "$github_name"

git add "$domains_file"
git commit -qm "Update domains"
git push -q

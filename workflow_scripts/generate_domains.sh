#!/bin/bash

raw_file="raw.txt"
domains_file="domains.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

grep -vE '^(#|$)' "$raw_file" > tmp1.txt

grep -vE '^(#|$)' "$domains_file" > tmpA.txt

comm -23 tmp1.txt tmpA.txt > tmp2.txt

grep '^www\.' tmp2.txt > tmp_with_www.txt

# comm is used here since both files are still in sorted order
comm -23 tmp2.txt tmp_with_www.txt > tmp_no_www.txt

awk '{sub(/^www\./, ""); print}' tmp_with_www.txt > tmp_no_www_new.txt

awk '{print "www."$0}' tmp_no_www.txt > tmp_with_www_new.txt

cat tmp_no_www_new.txt tmp_with_www_new.txt > tmp_flipped.txt

touch tmp_flipped_dead.txt

cat tmp_flipped.txt | xargs -I{} -P8 bash -c "
    if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
        echo {} >> tmp_flipped_dead.txt
    fi
"

grep -vxFf tmp_flipped_dead.txt tmp_flipped.txt > tmp_flipped_alive.txt

cat tmp_flipped_alive.txt >> tmp2.txt

sort -u tmp2.txt -o tmp3.txt

num_domains=$(wc -l < tmp3.txt)

echo "# Title: Jarelllama's Scam Blocklist
# Description: Blocklist for scam sites extracted from Google
# Homepage: https://github.com/jarelllama/Scam-Blocklist
# License: GNU GPLv3 (https://www.gnu.org/licenses/gpl-3.0.en.html)
# Last modified: $(date -u)
# Syntax: Domains
# Total number of domains: $num_domains
" | cat - tmp3.txt > "$domains_file"

rm tmp*.txt

git config user.email "$github_email"
git config user.name "$github_name"

git add "$domains_file"
git commit -qm "Update domains list"
git push -q

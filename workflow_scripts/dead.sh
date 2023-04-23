#!/bin/bash

domains_file="domains"
email="91372088+jarelllama@users.noreply.github.com"
name="jarelllama"

grep -vE '^(#|$)' "$domains_file" > tmp1.txt

touch tmp_dead.txt

cat tmp1.txt | xargs -I{} -P8 bash -c "
  if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
      echo {} >> tmp_dead.txt
      echo '{} (dead)'
  fi
"

comm -23 tmp1.txt <(sort tmp_dead.txt) > "$domains_file"

echo -e "\nTotal domains removed: $(wc -l < tmp_dead.txt)\n"

update_header

rm tmp*.txt

git config user.email "$email"
git config user.name "$name"

git add "$domains_file"
git commit -m "Remove dead domains"
git push

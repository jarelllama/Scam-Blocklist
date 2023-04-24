#!/bin/bash

domains_file="domains"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

grep -vE '^(#|$)' "$domains_file" > tmp1.txt

touch tmp_dead.txt

cat tmp1.txt | xargs -I{} -P8 bash -c "
  if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
      echo {} >> tmp_dead.txt
      echo '{} (dead)'
  fi
"

if ! [[ -s tmp_dead.txt ]]; then
    echo -e "\nNo dead domains found.\n"
    rm tmp*.txt
    exit 0
fi

comm -23 tmp1.txt <(sort tmp_dead.txt) > "$domains_file"

echo -e "\nDead domains:"
cat tmp_dead.txt

echo -e "\nTotal domains removed: $(wc -l < tmp_dead.txt)\n"

rm tmp*.txt

git config user.email "$github_email"
git config user.name "$github_name"

git add "$domains_file"
git commit -qm "Remove dead domains"
git push -q

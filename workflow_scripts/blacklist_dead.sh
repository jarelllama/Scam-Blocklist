#!/bin/bash

blacklist_file="blacklist.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

touch tmp_dead.txt

cat "$blacklist_file" | xargs -I{} -P4 bash -c "
  if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
      echo {} >> tmp_dead.txt
  fi
"

if ! [[ -s tmp_dead.txt ]]; then
    echo -e "\nNo dead domains found.\n"
    rm tmp*.txt
    exit 0
fi

comm -23 "$blacklist_file" <(sort tmp_dead.txt) > tmp1.txt

mv tmp1.txt "$blacklist_file"

echo -e "\nDead domains:"
cat tmp_dead.txt

echo -e "\nTotal domains removed: $(wc -l < tmp_dead.txt)\n"

rm tmp*.txt

git config user.email "$github_email"
git config user.name "$github_name"

git add "$domains_file"
git commit -qm "Remove dead domains"
git push -q

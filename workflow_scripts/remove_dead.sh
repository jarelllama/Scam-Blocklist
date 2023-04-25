#!/bin/bash

raw_file="data/raw.txt"
blacklist_file="blacklist.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

touch dead.tmp

cat "$raw_file" | xargs -I{} -P8 bash -c "
  if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
      echo {} >> dead.tmp
      echo '{} (dead)'
  fi
"

if ! [[ -s dead.tmp ]]; then
    echo -e "\nNo dead domains found.\n"
    rm *.tmp
    exit 0
fi

grep -vxFf dead.tmp "$raw_file" > raw.tmp

mv raw.tmp "$raw_file"

grep -vxFf dead.tmp "$blacklist_file" > blacklist.tmp

mv blacklist.tmp "$blacklist_file"

echo -e "\nDead domains:"
cat dead.tmp

echo -e "\nTotal domains removed: $(wc -l < dead.tmp)\n"

rm *.tmp

git config user.email "$github_email"
git config user.name "$github_name"

git add "$raw_file" "$blacklist_file"
git commit -qm "Remove dead domains"
git push -q

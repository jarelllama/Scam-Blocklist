#!/bin/bash

raw_file="data/raw.txt"
blacklist_file="blacklist.txt"
compressed_entries="data/compressed_entries.txt"
dead_domains_file="data/dead_domains.txt"
github_email='91372088+jarelllama@users.noreply.github.com'
github_name='jarelllama'

git config user.email "$github_email"
git config user.name "$github_name"

function remove_dead {
    grep -vxFf dead.tmp "$raw_file" > raw.tmp
    mv raw.tmp "$raw_file"

    grep -vxFf dead.tmp "$blacklist_file" > blacklist.tmp
    mv blacklist.tmp "$blacklist_file"

    awk '{print "||" $0 "^"}' dead.tmp > adblock_dead.tmp
    grep -vxFf adblock_dead.tmp "$compressed_entries" > compressed_entries.tmp
    mv compressed_entries.tmp "$compressed_entries"

    cat dead.tmp >> "$dead_domains_file"
    sort -u "$dead_domains_file" -o "$dead_domains_file"

    echo -e "\nDead domains:"
    cat dead.tmp

    echo -e "\nTotal domains removed: $(wc -l < dead.tmp)"
    
    git add "$raw_file" "$blacklist_file" "$compressed_entries" "$dead_domains_file"
    git commit -qm "Remove dead domains"
}

function add_resurrected {
    grep -vxFf dead_now_alive.tmp "$dead_domains_file" > dead_domains.tmp
    mv dead_domains.tmp "$dead_domains_file"

    cat dead_now_alive.tmp >> "$raw_file" 
    sort "$raw_file" -o "$raw_file"

    echo -e "\nPreviously dead domains that are alive again:"
    cat dead_now_alive.tmp

    echo -e "\nTotal domains added: $(wc -l < dead_now_alive.tmp)"
    
    git add "$raw_file" "$dead_domains_file"
    git commit -qm "Add resurrected domains"
}

touch dead.tmp
cat "$raw_file" | xargs -I{} -P8 bash -c "
  if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
      echo {} >> dead.tmp
  fi
"

touch dead_now_alive.tmp
cat "$dead_domains_file" | xargs -I{} -P8 bash -c "
  if ! dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
      echo {} >> dead_now_alive.tmp
  fi
"

if [[ -s dead.tmp ]]; then
    remove_dead
else
    echo -e "\nNo dead domains found."
fi

if [[ -s dead_now_alive.tmp ]]; then
    add_resurrected
fi

rm *.tmp

echo
git push -q

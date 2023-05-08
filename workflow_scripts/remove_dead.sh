#!/bin/bash

raw_file="data/raw.txt"
blacklist_file="blacklist.txt"
compressed_entries_file="data/compressed_entries.txt"
dead_domains_file="data/dead_domains.txt"
git_email='91372088+jarelllama@users.noreply.github.com'
git_name='jarelllama'

git config user.email "$git_email"
git config user.name "$git_name"

function check_resolving {
    > dead.tmp
    
    echo -e "\nLog:"

    cat "$1" | xargs -I{} -P8 bash -c '
        domain="$1"
        while true; do
            dig=$(dig @1.1.1.1 "$domain")
            if ! [[ "$dig" == *"timed out"* ]]; then
                break
            fi
            echo "$domain timed out. Retrying..."
            sleep 0.5
        done
        if [[ "$dig" == *"NXDOMAIN"* ]]; then
            echo "$domain (dead)"
            echo "$domain" >> dead.tmp
        fi
    ' -- {}
    
    sort -u dead.tmp -o dead.tmp
}

function remove_dead {
    comm -23 "$raw_file" dead.tmp > raw.tmp
    mv raw.tmp "$raw_file"

    comm -23 "$blacklist_file" dead.tmp > blacklist.tmp
    mv blacklist.tmp "$blacklist_file"

    awk '{print "||" $0 "^"}' dead.tmp > adblock_dead.tmp
    grep -vxFf adblock_dead.tmp "$compressed_entries_file" > compressed_entries_file.tmp
    mv compressed_entries_file.tmp "$compressed_entries_file"

    cat dead.tmp >> "$dead_domains_file"
    sort -u "$dead_domains_file" -o "$dead_domains_file"

    echo -e "\nAll dead domains removed:"
    cat dead.tmp

    echo -e "\nTotal domains removed: $(wc -l < dead.tmp)"
    
    git add "$raw_file" "$blacklist_file" "$compressed_entries_file" "$dead_domains_file"
    git commit -qm "Remove dead domains"
}

function add_resurrected {
    # change this to comm?
    grep -vxFf dead.tmp "$dead_domains_file" > dead_domains.tmp

    mv dead_domains.tmp "$dead_domains_file"

    cat dead_now_alive.tmp >> "$raw_file" 
    sort "$raw_file" -o "$raw_file"

    echo -e "\nPreviously dead domains that are alive again:"
    cat dead_now_alive.tmp

    echo -e "\nTotal domains added: $(wc -l < dead_now_alive.tmp)"
    
    git add "$raw_file" "$dead_domains_file"
    git commit -qm "Add resurrected domains"
}

check_resolving "$raw_file"

if [[ -s dead.tmp ]]; then
    remove_dead
else
    echo -e "\nNo dead domains found."
fi

check_resolving "$dead_domains_file"

comm -23 "$dead_domains_file" dead.tmp > alive.tmp

if [[ -s alive.tmp ]]; then
    add_resurrected
fi

rm *.tmp

echo
git push -q

#!/bin/bash

raw_file="data/raw.txt"
blacklist_file="blacklist.txt"
compressed_entries_file="data/compressed_entries.txt"
dead_domains_file="data/dead_domains.txt"

trap "find . -maxdepth 1 -type f -name '*.tmp' -delete" EXIT

function remove_dead {
    comm -23 "$raw_file" dead.tmp > raw.tmp
    mv raw.tmp "$raw_file"

    comm -23 "$blacklist_file" dead.tmp > blacklist.tmp
    mv blacklist.tmp "$blacklist_file"

    awk '{print "||" $0 "^"}' dead.tmp > adblock_dead.tmp
    grep -vxFf adblock_dead.tmp "$compressed_entries_file" > compressed_entries.tmp
    mv compressed_entries.tmp "$compressed_entries_file"

    cat dead.tmp >> "$dead_domains_file"
    sort -u "$dead_domains_file" -o "$dead_domains_file"

    echo -e "\nAll dead domains removed:"
    cat dead.tmp

    echo -e "\nTotal domains removed: $(wc -l < dead.tmp)"
    
    git add "$raw_file" "$blacklist_file" "$compressed_entries_file" "$dead_domains_file"
    git commit -qm "Remove dead domains"
}

function add_resurrected {
    comm -23 "$dead_domains_file" alive.tmp > dead_domains.tmp
    mv dead_domains.tmp "$dead_domains_file"

    cat alive.tmp >> "$raw_file" 
    sort "$raw_file" -o "$raw_file"

    echo -e "\nPreviously dead domains that are alive again:"
    cat alive.tmp

    echo -e "\nTotal domains added: $(wc -l < alive.tmp)"
    
    git add "$raw_file" "$dead_domains_file"
    git commit -qm "Add resurrected domains"
}

> dead.tmp
    
echo -e "\nChecking for dead domains...\n"

cat "$raw_file" | xargs -I{} -P8 bash -c '
    domain="$1"
    while true; do
        dig=$(dig @1.1.1.1 "$domain")
        [[ "$dig" =~ error|timed\ out ]] || break
        echo "$domain timed out."
        sleep 1
    done
    if [[ "$dig" == *"NXDOMAIN"* ]]; then
        echo "$domain (dead)"
        echo "$domain" >> dead.tmp
    fi
' -- {}
    
sort -u dead.tmp -o dead.tmp
    
> alive.tmp

echo -e "\nChecking for resurrected domains...\n"

cat "$dead_domains_file" | xargs -I{} -P8 bash -c '
    domain="$1"
    while true; do
        dig=$(dig @1.1.1.1 "$domain")
        [[ "$dig" =~ error|timed\ out ]] || break
        echo "$domain timed out."
        sleep 1
    done
    if ! [[ "$dig" == *"NXDOMAIN"* ]]; then
        echo "$domain (alive)"
        echo "$domain" >> alive.tmp
    fi
' -- {}
    
sort -u alive.tmp -o alive.tmp

if [[ -s dead.tmp ]]; then
    remove_dead
else
    echo -e "\nNo dead domains found."
fi

if [[ -s alive.tmp ]]; then
    add_resurrected
else
    echo -e "\nNo resurrected domains found."
fi

echo

#!/bin/bash

raw_file="data/raw.txt"
pending_file="pending_domains.txt"
search_terms_file="search_terms.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="data/toplist.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

declare -A retrieved_domains

user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"

echo -e "\nRetrieving domains...\n"

echo "Search terms:"

while IFS= read -r term; do
    if ! [[ "$term" =~ ^[[:space:]]*$|^# ]]; then
        encoded_term=$(echo "$term" | awk '{gsub(/[^[:alnum:]]+/,"+"); print}')

        google_search_url="https://www.google.com/search?q=\"${encoded_term}\"&num=100&filter=0&tbs=qdr:y"

        domains=$(curl -s --max-redirs 0 -H "User-Agent: $user_agent" "$google_search_url" | grep -oE '<a href="https:\S+"' | awk -F/ '{print $3}' | sort -u)

        echo "$term"
        echo "Domains retrieved: $(echo "$domains" | wc -w)"
        echo "--------------------------------------"
	for domain in $domains; do
            if [[ ${retrieved_domains["$domain"]+_} ]]; then
               continue 
            fi
            retrieved_domains["$domain"]=1
            echo "$domain" >> "$pending_file"
        done
    fi
done < "$search_terms_file"

num_retrieved=${#retrieved_domains[@]}

awk NF "$pending_file" > tmp1.tmp

tr '[:upper:]' '[:lower:]' < tmp1.tmp > tmp2.tmp

# No need to remove duplicates since all the retrieved domains are unique and the pending file is empty on every run
sort tmp2.tmp -o tmp2.tmp

comm -23 tmp2.tmp "$raw_file" > tmp3.tmp

echo "Domains removed:"

grep -Ff "$whitelist_file" tmp3.tmp | grep -vxFf "$blacklist_file" | awk '{print $0 " (whitelisted)"}'

grep -Ff "$whitelist_file" tmp3.tmp | grep -vxFf "$blacklist_file" > whitelisted.tmp

comm -23 tmp3.tmp whitelisted.tmp > tmp4.tmp

grep -E '\.(edu|gov)$' tmp4.tmp | awk '{print $0 " (TLD)"}'

grep -vE '\.(edu|gov)$' tmp4.tmp > tmp5.tmp

grep -vE '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' tmp5.tmp | awk '{print $0 " (invalid)"}'
    
grep -E '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' tmp5.tmp > tmp6.tmp

touch dead.tmp

cat tmp6.tmp | xargs -I{} -P4 bash -c "
        if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> dead.tmp
            echo '{} (dead)'
        fi
    "

grep -vxFf dead.tmp tmp6.tmp > tmp7.tmp

grep '^www\.' tmp7.tmp > with_www.tmp

comm -23 tmp7.tmp with_www.tmp > no_www.tmp

awk '{sub(/^www\./, ""); print}' with_www.tmp > no_www_new.tmp

awk '{print "www."$0}' no_www.tmp > with_www_new.tmp

cat no_www_new.tmp with_www_new.tmp > flipped.tmp

touch flipped_dead.tmp

cat flipped.tmp | xargs -I{} -P4 bash -c "
    if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
        echo {} >> flipped_dead.tmp
    fi
"

grep -vxFf flipped_dead.tmp flipped.tmp > flipped_alive.tmp

cat flipped_alive.tmp >> tmp7.tmp

sort tmp7.tmp -o tmp7.tmp

comm -23 tmp7.tmp "$raw_file" > "$pending_file"

if ! [[ -s "$pending_file" ]]; then
    echo -e "\nNo pending domains. Exiting...\n"
    rm *.tmp
    exit 0
fi

grep -xFf "$pending_file" "$toplist_file" | grep -vxFf "$blacklist_file" > in_toplist.tmp

if [[ -s in_toplist.tmp ]]; then
    echo -e "\nDomains found in toplist:"
    cat in_toplist.tmp
    echo -e "\nExiting...\n"
    rm *.tmp
    exit 1
fi

echo -e "\nTotal domains retrieved: $num_retrieved"
echo "Pending domains not in blocklist: $(wc -l < $pending_file)"
echo "Domains:"
cat "$pending_file"

echo -e "\nMerging with blocklist..."

num_before=$(wc -l < raw_file.tmp)

cat "$pending_file" >> raw_file.tmp 

sort raw_file.tmp -o "$raw_file"

num_after=$(wc -l < "$raw_file")

echo -e "\nTotal domains before: $num_before"
echo "Total domains added: $((num_after - num_before))"
echo "Final domains after: $num_after"

rm "$pending_file"

rm *.tmp

echo -e "\nPushing changes...\n"

git config user.email "$github_email"
git config user.name "$github_name"

git add "$raw_file"
git commit -qm "Automatic domain retrieval"
git push -q

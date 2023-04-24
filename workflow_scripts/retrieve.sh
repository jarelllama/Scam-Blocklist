#!/bin/bash

domains_file="domains"
pending_file="pending_domains.txt"
search_terms_file="search_terms.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="toplist.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

declare -A retrieved_domains

echo -e "\nRetrieving domains...\n"

echo "Search terms:"

while IFS= read -r term; do
    if ! [[ "$term" =~ ^[[:space:]]*$|^# ]]; then
        encoded_term=$(echo "$term" | awk '{gsub(/[^[:alnum:]]+/,"+"); print}')

        user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"

        google_search_url="https://www.google.com/search?q=\"${encoded_term}\"&num=100&filter=0&tbs=qdr:y"

        domains=$(curl -s --max-redirs 0 -H "User-Agent: $user_agent" "$google_search_url" | grep -oE '<a href="https:\S+"' | awk -F/ '{print $3}' | sort -u)

        echo "$term"

        echo "Domains retrieved: $(echo "$domains" | wc -w)"
        echo "--------------------------------------------"

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

grep -vE '^(#|$)' "$domains_file" > tmp_domains_file.txt

awk NF "$pending_file" > tmp1.txt

tr '[:upper:]' '[:lower:]' < tmp1.txt > tmp2.txt

sort -u tmp2.txt -o tmp3.txt

comm -23 tmp3.txt tmp_domains_file.txt > tmp4.txt

echo "Domains removed:"

grep -Ff "$whitelist_file" tmp4.txt | grep -vxFf "$blacklist_file" | awk '{print $0 " (whitelisted)"}'

grep -Ff "$whitelist_file" tmp4.txt | grep -vxFf "$blacklist_file" > tmp_whitelisted.txt

comm -23 tmp4.txt <(sort tmp_whitelisted.txt) > tmp5.txt

grep -E '\.(edu|gov)$' tmp5.txt | awk '{print $0 " (TLD)"}'

grep -vE '\.(edu|gov)$' tmp5.txt > tmp6.txt

grep -vE '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' tmp6.txt | awk '{print $0 " (invalid)"}'

grep -E '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' tmp6.txt > tmp7.txt

touch tmp_dead.txt

cat tmp7.txt | xargs -I{} -P4 bash -c "
    if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
        echo {} >> tmp_dead.txt
        echo '{} (dead)'
    fi
"

comm -23 tmp7.txt <(sort tmp_dead.txt) > tmp8.txt

grep '^www\.' tmp8.txt > tmp_with_www.txt

grep -vxFf tmp_with_www.txt tmp8.txt > tmp_no_www.txt

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

cat tmp_flipped_alive.txt >> tmp8.txt

sort -u tmp8.txt -o tmp9.txt

comm -23 tmp9.txt tmp_domains_file.txt > "$pending_file"

if ! [[ -s "$pending_file" ]]; then
    echo -e "\nNo pending domains. Exiting...\n"
    rm tmp*.txt
    exit 0
fi

grep -xFf "$pending_file" "$toplist_file" | grep -vxFf "$blacklist_file" > tmp_in_toplist.txt

if [[ -s tmp_in_toplist.txt ]]; then
    echo -e "\nDomains found in toplist:"
    grep -xFf "$pending_file" "$toplist_file" | grep -vxFf "$blacklist_file"
    echo -e "\nExiting...\n"
    rm tmp*.txt
    exit 1
fi

echo -e "\nTotal domains retrieved: $num_retrieved"
echo "Pending domains not in blocklist: $(wc -l < $pending_file)"
echo "Domains:"
cat "$pending_file"

echo -e "\nMerging with blocklist..."

num_before=$(wc -l < tmp_domains_file.txt)

cat "$pending_file" >> tmp_domains_file.txt 

sort -u tmp_domains_file.txt -o "$domains_file"

num_after=$(wc -l < "$domains_file")

echo -e "\nTotal domains before: $num_before"
echo "Total domains added: $((num_after - num_before))"
echo "Final domains after: $num_after"

rm "$pending_file"

rm tmp*.txt

echo -e "\nPushing changes...\n"

git config user.email "$github_email"
git config user.name "$github_name"

git add "$domains_file"
git commit -m "Automatically update domains"
git push

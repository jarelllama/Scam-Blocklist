#!/bin/bash

raw_file="data/raw.txt"
pending_file="pending_domains.txt"
search_terms_file="search_terms.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="data/toplist.txt"
dead_domains_file="data/dead_domains.txt"
edit_script="edit.sh"
github_email='91372088+jarelllama@users.noreply.github.com'
github_name='jarelllama'

git config user.email "$github_email"
git config user.name "$github_name"

if [[ -s "$pending_file" ]]; then
    read -n 1 -p $'\n'"$pending_file is not empty. Do you want to empty it? (Y/n): "  answer
    echo
    if [[ "$answer" =~ ^[Yy]$ ]] || [[ -z "$answer" ]]; then
        > "$pending_file"
    fi
fi

debug=0
unattended=0
time_filter='a'

for arg in "$@"; do
    if [[ "$arg" == 'd' ]]; then
        debug=1
    elif [[ "$arg" == 'u' ]]; then
        unattended=1
        time_filter='y'
    else
        time_filter="$arg"
    fi
done

if [[ "$unattended" -eq 0 ]]; then
    echo -e "\nRemember to pull the latest changes first!"
else
    echo -e "\nRetrieving domains..."
fi

declare -A retrieved_domains

user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36'

echo -e "\nSearch filter: $time_filter"
echo "Search terms:"

# A blank IFS ensures the entire search term is read
while IFS= read -r term; do
    if ! [[ "$term" =~ ^[[:space:]]*$|^# ]]; then
        # gsub replaces consecutive non-alphanumeric characters with a single plus sign
        encoded_term=$(echo "$term" | awk '{gsub(/[^[:alnum:]]+/,"+"); print}')

        google_search_url="https://www.google.com/search?q=\"${encoded_term}\"&num=100&filter=0&tbs=qdr:$time_filter"

        domains=$(curl -s --max-redirs 0 -H "User-Agent: $user_agent" "$google_search_url" | grep -oE '<a href="http\S+"' | awk -F/ '{print $3}' | grep -vxF 'www.google.com' | sort -u)

        echo "$term"

        if [[ "$debug" -eq 1 ]]; then
            echo "$domains"
        fi

        # wc -w does a better job than wc -l for counting domains in this case
        echo "Domains retrieved: $(echo "$domains" | wc -w)"
        echo "--------------------------------------"

        # Check if each domain is in the retrieved domains associative array
        # Note that quoting $domains causes errors
	for domain in $domains; do
            if [[ ${retrieved_domains["$domain"]+_} ]]; then
               continue 
            fi
            # Add the unique domain to the associative array
            retrieved_domains["$domain"]=1
            echo "$domain" >> "$pending_file"
        done
    fi
done < "$search_terms_file"

num_retrieved=${#retrieved_domains[@]}

function filter_pending {
    cp "$pending_file" "$pending_file.bak"

    tr '[:upper:]' '[:lower:]' < "$pending_file" > 1.tmp

    # Duplicates are removed for when the pending file isn't cleared
    # Note that sort writes to a temporary file before moving it to the output file. That's why the input and output can be the same
    sort -u 1.tmp -o 1.tmp

    # This removes the majority of pending domains and makes the further filtering more efficient
    comm -23 1.tmp "$raw_file" > 2.tmp
    
    comm -23 2.tmp "$dead_domains_file" > 3.tmp
    
    if ! [[ -s 3.tmp ]]; then
        echo -e "\nNo retrieved domains.\n"
        rm *.tmp
        exit 0
    fi

    echo -e "\nDomains removed:"

    grep -Ff "$whitelist_file" 3.tmp | grep -vxFf "$blacklist_file" | awk '{print $0 " (whitelisted)"}'

    grep -Ff "$whitelist_file" 3.tmp | grep -vxFf "$blacklist_file" > whitelisted.tmp

    comm -23 3.tmp whitelisted.tmp > 4.tmp

    grep -E '\.(edu|gov)$' 4.tmp | awk '{print $0 " (TLD)"}'

    grep -vE '\.(edu|gov)$' 4.tmp > 5.tmp

    # This regex checks for valid domains
    grep -vE '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' 5.tmp | awk '{print $0 " (invalid)"}'
    
    grep -E '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' 5.tmp > 6.tmp

    # grep outputs an error if this file is missing
    touch dead.tmp

    # Use parallel processing
    cat 6.tmp | xargs -I{} -P6 bash -c "
        if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> dead.tmp
            echo '{} (dead)'
        fi
    "

    # It appears that the dead file isn't always sorted
    # Both comm and grep were tested here. When only small files need to be sorted the performance is generally the same. Otherwise, sorting big files with comm is slower than just using grep
    grep -vxFf dead.tmp 6.tmp > pending.tmp

    # This portion of code removes www subdomains for domains that have it and adds the www subdomains to those that don't. This effectively flips which domains have the www subdomain

    grep '^www\.' pending.tmp > with_www.tmp

    comm -23 pending.tmp with_www.tmp > no_www.tmp

    awk '{sub(/^www\./, ""); print}' with_www.tmp > no_www_new.tmp

    awk '{print "www."$0}' no_www.tmp > with_www_new.tmp

    cat no_www_new.tmp with_www_new.tmp > 1.tmp

    # Remove flipped domains that are already in the blocklist
    grep -vxFf "$raw_file" 1.tmp > flipped.tmp

    touch flipped_alive.tmp

    cat flipped.tmp | xargs -I{} -P6 bash -c "
        if ! dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> flipped_alive.tmp
        fi
    "

    cat flipped_alive.tmp >> pending.tmp

    # Duplicates are removed again from the pending file for when the file isn't cleared and flipped domains might be duplicated
    sort -u pending.tmp -o "$pending_file"

    if ! [[ -s "$pending_file" ]]; then
        echo -e "\nNo pending domains.\n"
        rm *.tmp
        exit 0
    fi

    echo -e "\nTotal domains retrieved: $num_retrieved"
    echo "Pending domains not in blocklist: $(wc -l < $pending_file)"
    echo "Domains:"
    cat "$pending_file"
    
    # About 8x faster than comm due to not needing to sort the toplist
    grep -xFf "$pending_file" "$toplist_file" | grep -vxFf "$blacklist_file" > in_toplist.tmp

    if [[ -s in_toplist.tmp ]]; then
        echo -e "\nDomains in toplist:"
        cat in_toplist.tmp
        if [[ "$unattended" -eq 1 ]]; then
            echo -e "\nExiting...\n"
            rm *.tmp
            exit 1
        fi
    else
        echo -e "\nNo domains found in toplist."
    fi
    
    rm *.tmp
}

function merge_pending {
    cp "$raw_file" "$raw_file.bak"

    num_before=$(wc -l < "$raw_file")

    cat "$pending_file" >> "$raw_file" 

    sort "$raw_file" -o "$raw_file"

    num_after=$(wc -l < "$raw_file")

    awk '{sub(/^www\./, ""); print}' "$pending_file" > unique_sites.tmp
    
    sort -u unique_sites.tmp -o unique_sites.tmp

    echo -e "\nTotal domains before: $num_before"
    echo "Total domains added: $((num_after - num_before))"
    echo "Total domains after: $num_after"
    echo "Unique sites added: $(wc -l < unique_sites.tmp)"

    > "$pending_file"

    rm *.tmp

    if [[ unattended -eq 0 ]]; then
        read -n 1 -p $'\nDo you want to push the updated blocklist? (Y/n): ' answer
        echo
        if ! [[ "$answer" =~ ^[Yy]$ ]] && ! [[ -z "$answer" ]]; then
            exit 0
        fi
        commit_msg='Manual domains retrieval'
    else
        echo -e "\nPushing changes..."
        commit_msg='Automatic domains retrieval'
    fi

    echo

    # Push white/black lists too for when the user modifies them
    git add "$raw_file" "$whitelist_file" "$blacklist_file"
    git commit -m "$commit_msg"
    git push

    exit 0
}

filter_pending

if [[ "$unattended" -eq 1 ]]; then
    echo -e "\nMerging with blocklist..."
    merge_pending
fi

while true; do
    echo -e "\nPending Domains Menu:"
    echo "1. Merge with blocklist"
    echo "2. Edit lists"
    echo "3. Run filter again"
    echo "x. Save pending and exit"
    read choice

    case "$choice" in
        1)
            echo "Merge with blocklist"
            merge_pending
            ;;
        2)
            # Call editing script
            echo "Edit lists"
            echo -e "\nEnter 'x' to go back to the previous menu."
            source "$edit_script"
            continue
            ;;
        3)
            echo "Run filter again"
            cp "$pending_file.bak" "$pending_file"
            filter_pending
            continue
            ;;
        x)
            if [[ -f *.tmp ]]; then
                rm *.tmp
            fi
            exit 0
            ;;
        *)
            echo -e "\nInvalid option."
            continue
            ;;
    esac
done

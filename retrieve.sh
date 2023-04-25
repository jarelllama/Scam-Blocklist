#!/bin/bash

raw_file="data/raw.txt"
pending_file="pending_domains.txt"
search_terms_file="search_terms.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="data/toplist.txt"
edit_script="edit.sh"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

echo -e "\nRemember to pull the latest changes first!"

if [[ -s "$pending_file" ]]; then
    read -p $'\n'"$pending_file is not empty. Do you want to empty it? (Y/n): " answer
    if ! [[ "$answer" == "n" ]]; then
        > "$pending_file"
    fi
fi

debug=0

# Set the default time filter to past 3 years
time_filter="y3"

for arg in "$@"; do
    if [[ "$arg" == "d" ]]; then
        debug=1
    # Set the time filter to argument specified on runtime
    else
        time_filter="$arg"
    fi
done

declare -A retrieved_domains

echo -e "\nSearch filter: $time_filter"
echo "Search terms:"

# A blank IFS ensures the entire search term is read
while IFS= read -r term; do
    if ! [[ "$term" =~ ^[[:space:]]*$|^# ]]; then
        # gsub is used here to replace consecutive non-alphanumeric characters with a single plus sign
        encoded_term=$(echo "$term" | awk '{gsub(/[^[:alnum:]]+/,"+"); print}')

        user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"

        google_search_url="https://www.google.com/search?q=\"${encoded_term}\"&num=100&filter=0&tbs=qdr:$time_filter"

        # Search Google and extract all domains
        # Duplicates are removed here for accurate counting of the retrieved domains by each search term
        domains=$(curl -s --max-redirs 0 -H "User-Agent: $user_agent" "$google_search_url" | grep -oE '<a href="https:\S+"' | awk -F/ '{print $3}' | sort -u)

        echo "$term"

        if [[ "$debug" -eq 1 ]]; then
            echo "$domains"
        fi

        # wc -w does a better job than wc -l for counting domains in this case
        echo "Domains retrieved: $(echo "$domains" | wc -w)"
        echo "--------------------------------------------"

        # Check if each domain is already in the retrieved domains associative array
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

    grep -vE '^(#|$)' "$raw_file" > raw.tmp

    awk NF "$pending_file" > tmp1.tmp

    tr '[:upper:]' '[:lower:]' < tmp1.tmp > tmp2.tmp

    # Note that sort writes the sorted list to a temporary file before moving it to the output file. Therefore the input and output file can be the same file
    sort -u tmp2.tmp -o tmp2.tmp

    # This removes the majority of pending domains and makes the further filtering more efficient
    comm -23 tmp2.tmp raw.tmp > tmp3.tmp

    echo "Domains removed:"

    comm -12 tmp3.tmp "$whitelist_file" | grep -vxFf "$blacklist_file" | awk '{print $0 " (whitelisted)"}'

    comm -12 tmp3.tmp "$whitelist_file" | grep -vxFf "$blacklist_file" > whitelisted.tmp

    comm -23 tmp3.tmp whitelisted.tmp > tmp4.tmp

    grep -E '\.(edu|gov)$' tmp4.tmp | awk '{print $0 " (TLD)"}'

    grep -vE '\.(edu|gov)$' tmp4.tmp > tmp5.tmp

    # This regex checks for valid domains
    grep -vE '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' tmp5.tmp | awk '{print $0 " (invalid)"}'
    
    grep -E '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' tmp5.tmp > tmp6.tmp

    touch dead.tmp

    # Use parallel processing
    cat tmp6.tmp | xargs -I{} -P4 bash -c "
        if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> dead.tmp
            echo '{} (dead)'
        fi
    "

    # Both comm and grep were tested here. When only small files need to be sorted the performance is generally the same. Otherwise, sorting big files with comm is slower than just using grep
    grep -vxFf dead.tmp tmp6.tmp > tmp7.tmp

    # This portion of code removes www subdomains for domains that have it and adds the www subdomains to those that don't. This effectively flips which domains have the www subdomain
    # This reduces the number of domains checked by the dead domains filter. Thus, improves efficiency

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

    cat flipped_alive.tmp >> tmp8.tmp

    # Duplicates are removed here for when the pending file isn't cleared and flipped domains are duplicated
    sort -u tmp8.tmp -o tmp8.tmp

    # Remove any new flipped domains that might already be in the blocklist
    # This is done for accurate counting
    comm -23 tmp8.tmp raw.tmp > "$pending_file"

    echo -e "\nTotal domains retrieved: $num_retrieved"
    echo "Pending domains not in blocklist: $(wc -l < $pending_file)"
    echo "Domains:"
    cat "$pending_file"
    echo -e "\nDomains in toplist:"
    # About 8x faster than comm due to not needing to sort the toplist
    grep -xFf "$pending_file" "$toplist_file" | grep -vxFf "$blacklist_file"
    
    rm *.tmp
}

function merge_pending {
    echo "Merge with blocklist"

    cp "$raw_file" "$raw_file.bak"

    grep -vE '^(#|$)' "$raw_file" > raw.tmp

    num_before=$(wc -l < raw.tmp)

    cat "$pending_file" >> raw.tmp 

    sort -u raw.tmp -o "$raw_file"

    num_after=$(wc -l < "$raw_file")

    echo "--------------------------------------------"
    echo "Total domains before: $num_before"
    echo "Total domains added: $((num_after - num_before))"
    echo "Final domains after: $num_after"

    > "$pending_file"

    rm *.tmp

    read -p $'\nDo you want to push the updated blocklist? (y/N): ' answer
    if [[ "$answer" != "y" ]]; then
        exit 0
    fi

    echo ""

    git config user.email "$github_email"
    git config user.name "$github_name"

    git add "$raw_file" "$whitelist_file" "$blacklist_file"
    git commit -m "Update $raw_file"
    git push

    exit 0
}

filter_pending

while true; do
    echo -e "\nPending Domains Menu:"
    echo "1. Merge with blocklist"
    echo "2. Edit lists"
    echo "3. Run filter again"
    echo "x. Save pending and exit"
    read choice

    case "$choice" in
        1)
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

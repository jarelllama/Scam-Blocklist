#!/bin/bash

raw_file="data/raw.txt"
pending_file="pending_domains.txt"
search_terms_file="search_terms.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="data/toplist.txt"
dead_domains_file="data/dead_domains.txt"
edit_script="edit.sh"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

if [[ -s "$pending_file" ]]; then
    read -p $'\n'"$pending_file is not empty. Do you want to empty it? (Y/n): " answer
    if [[ "$answer" != "n" ]]; then
        > "$pending_file"
    fi
fi

# Default values
debug=0
unattended=0
time_filter="a"

for arg in "$@"; do
    if [[ "$arg" == "d" ]]; then
        debug=1
    elif [[ "$arg" == "u" ]]; then
        unattended=1
        time_filter="y"
        echo -e "\nRetrieving domains..."
    else
        time_filter="$arg"
    fi
done

if [[ "$unattended" -eq 0 ]]; then
    echo -e "\nRemember to pull the latest changes first!"
fi

declare -A retrieved_domains

user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"

echo -e "\nSearch filter: $time_filter"
echo "Search terms:"

# A blank IFS ensures the entire search term is read
while IFS= read -r term; do
    if ! [[ "$term" =~ ^[[:space:]]*$|^# ]]; then
        # gsub is used here to replace consecutive non-alphanumeric characters with a single plus sign
        encoded_term=$(echo "$term" | awk '{gsub(/[^[:alnum:]]+/,"+"); print}')

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
        echo "--------------------------------------"

        # Check if each domain is already in the retrieved domains associative array
        # Note that quoting $domains causes errors
	for domain in $domains; do
            if [[ ${retrieved_domains["$domain"]+_} ]]; then
               continue 
            fi
            # Add the unique domain to the associative array
            retrieved_domains["$domain"]=1
            # Note that echo creates the file when it doesn't already exist
            echo "$domain" >> "$pending_file"
        done
    fi
done < "$search_terms_file"

num_retrieved=${#retrieved_domains[@]}

function filter_pending {
    cp "$pending_file" "$pending_file.bak"

    awk NF "$pending_file" > tmp1.tmp

    tr '[:upper:]' '[:lower:]' < tmp1.tmp > tmp2.tmp

    # Duplicates removed for when pending file isn't cleared
    # Note that sort writes the sorted list to a temporary file before moving it to the output file. Therefore the input and output files can be the same
    sort -u tmp2.tmp -o tmp2.tmp

    # This removes the majority of pending domains and makes the further filtering more efficient
    comm -23 tmp2.tmp "$raw_file" > tmp3.tmp

    echo -e "\nDomains removed:"

    grep -Ff "$whitelist_file" tmp3.tmp | grep -vxFf "$blacklist_file" | awk '{print $0 " (whitelisted)"}'

    grep -Ff "$whitelist_file" tmp3.tmp | grep -vxFf "$blacklist_file" > whitelisted.tmp

    comm -23 tmp3.tmp whitelisted.tmp > tmp4.tmp

    grep -E '\.(edu|gov)$' tmp4.tmp | awk '{print $0 " (TLD)"}'

    grep -vE '\.(edu|gov)$' tmp4.tmp > tmp5.tmp

    # This regex checks for valid domains
    grep -vE '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' tmp5.tmp | awk '{print $0 " (invalid)"}'
    
    grep -E '^[[:alnum:].-]+\.[[:alnum:]]{2,}$' tmp5.tmp > tmp6.tmp

    # Remove known dead domains to make the dead domains check more efficient
    comm -23 tmp6.tmp "$dead_domains_file" > tmp7.tmp

    # The file is created here for when there are no dead domains so the echo command doesn't create it
    # When it is missing the grep command shows an error
    touch dead.tmp

    # Use parallel processing
    cat tmp7.tmp | xargs -I{} -P4 bash -c "
        if dig @1.1.1.1 {} | grep -Fq 'NXDOMAIN'; then
            echo {} >> dead.tmp
            echo '{} (dead)'
        fi
    "

    # Seems like the dead.tmp isn't always sorted
    # Both comm and grep were tested here. When only small files need to be sorted the performance is generally the same. Otherwise, sorting big files with comm is slower than just using grep
    grep -vxFf dead.tmp tmp7.tmp > tmp8.tmp

    cat dead.tmp >> "$dead_domains_file"

    sort -u "$dead_domains_file" -o "$dead_domains_file"

    # This portion of code removes www subdomains for domains that have it and adds the www subdomains to those that don't. This effectively flips which domains have the www subdomain
    # This reduces the number of domains checked by the dead domains filter. Thus, improves efficiency

    grep '^www\.' tmp8.tmp > with_www.tmp

    comm -23 tmp8.tmp with_www.tmp > no_www.tmp

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

    # Note that dead flipped domains here aren't added to the dead domaina file since the whole list is checked for flip domains on a schedule. Any new flipped domains then will be added

    # Duplicates are removed here for when the pending file isn't cleared and flipped domains are duplicated
    sort -u tmp8.tmp -o tmp8.tmp

    # Remove any new flipped domains that might already be in the blocklist
    # This is done for accurate counting
    comm -23 tmp8.tmp "$raw_file" > "$pending_file"

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
        read -p $'\nDo you want to push the updated blocklist? (Y/n): ' answer
        if [[ "$answer" == "n" ]]; then
            exit 0
        fi
        commit_msg="Manual domains retrieval"
    else
        echo -e "\nPushing changes..."
        commit_msg="Automatic domains retrieval"
    fi

    echo ""

    git config user.email "$github_email"
    git config user.name "$github_name"

    # Commit white/black lists too for when the user modified them
    git add "$raw_file" "$whitelist_file" "$blacklist_file" "$dead_domains_file"
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

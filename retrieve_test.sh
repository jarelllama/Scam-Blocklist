#!/bin/bash

raw_file="data/raw.txt"
pending_file="pending_domains.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="data/toplist.txt"
dead_domains_file="data/dead_domains.txt"
compressed_entries_file="data/compressed_entries.txt"
stats_file="data/stats.txt"
edit_script="edit.sh"

trap "find . -maxdepth 1 -type f -name '*.tmp' -delete" EXIT

debug='false'
unattended='false'
use_pending_only='false'
time_filter='a'

for arg in "$@"; do
    if [[ "$arg" == 'd' ]]; then
        debug='true'
    elif [[ "$arg" == 'p' ]]; then
        use_pending_only='true'
    elif [[ "$arg" == 'u' ]]; then
        unattended='true'
        time_filter='y'
    else
        time_filter="$arg"
    fi
done

if [[ -s "$pending_file" ]] && ! "$use_pending_only"; then
    read -n1 -p $'\n'"$pending_file is not empty. Do you want to empty it? (Y/n): "  answer
    echo
    if [[ "$answer" =~ ^[Yy]$ ]] || [[ -z "$answer" ]]; then
        > "$pending_file"
    fi
fi

cut -d. -f2- "$compressed_entries_file" > scam_wildcards.tmp
sort -u scam_wildcards.tmp -o scam_wildcards.tmp
search_terms_file=scam_wildcards.tmp

if "$unattended"; then
    echo -e "\nRetrieving domains..."
else
    echo -e "\nRemember to pull the latest changes first!"
fi

function retrieve_domains {
    echo -e "\nSearch filter: $time_filter"
    echo "Search terms:"

    user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36'

    # A blank IFS ensures the entire search term is read
    while IFS= read -r term; do
        # Skip empty lines or comments
        [[ "$term" =~ ^[[:space:]]*$|^# ]] && continue
        # gsub replaces consecutive non-alphanumeric characters with a single plus sign
        #encoded_term=$(echo "$term" | awk '{gsub(/[^[:alnum:]]+/,"+"); print}')

        google_search_url="https://www.google.com/search?q=site:${term}\"&num=100&filter=0&tbs=qdr:${time_filter}"

        domains=$(curl -s --max-redirs 0 -H "User-Agent: $user_agent" "$google_search_url" \
            | grep -oE '<a href="http\S+"' \
            | awk -F/ '{print $3}' \
            | grep -vxF 'www.google.com' \
            | sort -u)

        term=$(echo "$term" | cut -c 1-350)
        echo "${term}..."

        "$debug" && echo "$domains"

        # wc -w does a better job than wc -l for counting domains in this case
        echo "Domains retrieved: $(echo "$domains" | wc -w)"
        echo "--------------------------------------"

      	[[ -n "$domains" ]] && echo "$domains" >> "$pending_file"
    done < "$search_terms_file"

    sort -u "$pending_file" -o "$pending_file"

    if ! [[ -s "$pending_file" ]]; then
        echo -e "\nNo retrieved domains. Try changing VPN servers.\n"
        exit 1
    fi

    total_retrieved=$(wc -l < "$pending_file")

    echo -e "\nTotal domains retrieved: $total_retrieved"
}

function filter_pending {
    cp "$pending_file" "${pending_file}.bak"

    tr '[:upper:]' '[:lower:]' < "$pending_file" > 1.tmp

    # Duplicates are removed for when the pending file isn't cleared
    # Note that sort writes to a temporary file before moving it to the output file
    # That's why the input and output can be the same
    sort -u 1.tmp -o 1.tmp

    comm -23 1.tmp "$raw_file" > 2.tmp

    comm -23 2.tmp "$dead_domains_file" > 3.tmp

    echo -e "\nDomains removed:"

    grep -Ff "$whitelist_file" 3.tmp | grep -vxFf "$blacklist_file" | awk '{print $0 " (whitelisted)"}'
    grep -Ff "$whitelist_file" 3.tmp | grep -vxFf "$blacklist_file" > whitelisted.tmp
    comm -23 3.tmp whitelisted.tmp > 4.tmp

    grep -E '\.(gov|edu)(\.[a-z]{2})?$' 4.tmp | awk '{print $0 " (TLD)"}'
    grep -vE '\.(gov|edu)(\.[a-z]{2})?$' 4.tmp > 5.tmp

    # This regex matches valid domains. This includes puny code TLDs (.xn--*)
    grep -vE '^[[:alnum:].-]+\.[[:alnum:]-]{2,}$' 5.tmp | awk '{print $0 " (invalid)"}'
    grep -E '^[[:alnum:].-]+\.[[:alnum:]-]{2,}$' 5.tmp > 6.tmp

    # Duplicates are removed again for when the pending file isn't cleared and there are duplicate newly added domains
    sort -u 6.tmp -o "$pending_file"

    if ! [[ -s "$pending_file" ]]; then
        echo -e "\nNo pending domains.\n"
        exit 0
    fi

    echo -e "\nPending domains not in blocklist: $(wc -l < $pending_file)"
    echo "Domains:"
    cat "$pending_file"
    
    comm -12 "$pending_file" "$toplist_file" | grep -vxFf "$blacklist_file" > in_toplist.tmp

    if [[ -s in_toplist.tmp ]]; then
        echo -e "\nDomains in toplist:"
        cat in_toplist.tmp
        if "$unattended"; then
            echo -e "\nExiting...\n"
            exit 1
        fi
    else
        echo -e "\nNo domains found in toplist."
    fi
    
    rm ./*.tmp
}

function merge_pending {
    cp "$raw_file" "${raw_file}.bak"

    num_before=$(wc -l < "$raw_file")

    cat "$pending_file" >> "$raw_file" 

    sort "$raw_file" -o "$raw_file"

    num_after=$(wc -l < "$raw_file")

    awk '{sub(/^www\./, ""); print}' "$pending_file" > 1.tmp

    awk '{sub(/^m\./, ""); print}' 1.tmp > unique_sites.tmp
    
    sort -u unique_sites.tmp -o unique_sites.tmp

    unique_count=$(wc -l < unique_sites.tmp)

    echo -e "\nTotal domains before: $num_before"
    echo "Total domains added: $((num_after - num_before))"
    echo "Total domains after: $num_after"
    echo "Unique sites added: $unique_count"

    > "$pending_file"
    
    if "$unattended"; then
        echo -e "\nPushing changes..."
        commit_msg='Automatic domain retrieval'
        
        previous_count=$(sed -n '10p' "$stats_file")
        new_count=$((previous_count + unique_count))
        sed -i "10s/.*/${new_count}/" "$stats_file"
    else
        read -n1 -p $'\nDo you want to push the blocklist? (Y/n): ' answer
        echo
        if [[ "$answer" =~ ^[Yy]$ ]] || [[ -z "$answer" ]]; then
            commit_msg="Manual domain retrieval"
        else
            exit 0
        fi
    fi

    echo

    # Push white/black lists too for when they are modified through the editing script
    git add "$raw_file" "$stats_file" "$whitelist_file" "$blacklist_file"
    git commit -m "$commit_msg"
    git push

    exit 0
}

"$use_pending_only" || retrieve_domains

filter_pending

if "$unattended"; then
    echo -e "\nMerging with blocklist..."
    merge_pending
fi

while true; do
    echo -e "\nPending Domains Menu:"
    echo "m. Merge with blocklist"
    echo "e. Edit lists"
    echo "r. Run filter again"
    echo "x. Save pending and exit"
    read choice

    case "$choice" in
        m)
            echo "Merge with blocklist"
            merge_pending
            ;;
        e)
            # Call the editing script
            echo "Edit lists"
            echo -e "\nEnter 'x' to go back to the previous menu."
            source "$edit_script"
            ;;
        r)
            echo "Run filter again"
            cp "${pending_file}.bak" "$pending_file"
            filter_pending
            ;;
        x)
            exit 0
            ;;
        *)
            echo -e "\nInvalid option."
            ;;
    esac
done
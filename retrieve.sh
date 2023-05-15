#!/bin/bash

raw_file="data/raw.txt"
pending_file="pending_domains.txt"
search_terms_file="search_terms.txt"
whitelist_file="data/whitelist.txt"
blacklist_file="data/blacklist.txt"
toplist_file="data/toplist.txt"
subdomains_file="data/subdomains.txt"
dead_domains_file="data/dead_domains.txt"
optimised_entries="data/optimised_entries.txt"
optimiser_whitelist="data/optimiser_whitelist.txt"
stats_file="data/stats.txt"
edit_script="edit.sh"

function on_exit {
    echo -e "\nExiting..."
    find . -maxdepth 1 -type f -name '*.tmp' -delete
}

trap 'on_exit' EXIT

debug='false'
unattended='false'
use_pending_only='false'
time_filter='a'

while getopts ":dupt:" option; do
    case $option in
        d)
            debug='true' ;;
        u)
            unattended='true'
            time_filter='y'
            ;;
        p)
            use_pending_only='true' ;;
        t)
            time_filter="$OPTARG" ;;
        \?)
            echo "Invalid option: -$OPTARG"
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument"
            exit 1
            ;;
    esac
done

function retrieve_domains {
    if [[ -s "$pending_file" ]]; then
        read -rp $'\nThe pending file is not empty. Empty it? (Y/n): ' answer
        if [[ "$answer" =~ ^[Yy]$ || -z "$answer" ]]; then
            echo -e "\nEmptied the pending file."
            > "$pending_file"
            sleep 0.5
        fi
    fi

    echo -e "\nSearch filter: $time_filter"
    echo "Search terms:"

    user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36'

    term_num=1

    # A blank IFS ensures the entire search term is read
    while IFS= read -r term; do
        # Skip empty lines or comments
        [[ "$term" =~ ^[[:space:]]*$|^# ]] && continue

        # gsub replaces consecutive non-alphanumeric characters with a single plus sign
        encoded_term=$(echo "$term" | awk '{gsub(/[^[:alnum:]]+/,"+"); print}')

        search_url="https://www.google.com/search?q=\"${encoded_term}\"&num=100&filter=0&tbs=qdr:${time_filter}"

        domains=$(curl -s --max-redirs 0 -H "User-Agent: $user_agent" "$search_url" \
            | grep -oE '<a href="http\S+"' \
            | awk -F/ '{print $3}' \
            | sort -u \
            | grep -vxF 'www.google.com')

        term=$(echo "$term" | cut -c 1-300)
        echo "${term_num}. ${term}..."
        ((term_num++))

        if [[ -z "$domains" ]]; then
            echo "Domains retrieved: 0"
            echo "--------------------------------------"
            continue
        fi

        "$debug" && echo "$domains"
        
        echo "$domains" > domains.tmp

        # Remove subdomains
        while read -r subdomain; do
            sed -i "s/^${subdomain}\.//" domains.tmp
        done < "$subdomains_file"
        sort -u domains.tmp -o domains.tmp

        cat domains.tmp >> "$pending_file"

        echo "Domains retrieved: $(wc -l < domains.tmp)"
        echo "--------------------------------------"
    done < "$search_terms_file"

    if ! [[ -s "$pending_file" ]]; then
        echo -e "\nNo domains retrieved."
        exit 1
    fi
}

function check_toplist {
    while true; do
        sleep 0.5

        comm -12 "$pending_file" "$toplist_file" \
            | grep -vxFf "$blacklist_file" > in_toplist.tmp

        if ! [[ -s in_toplist.tmp ]]; then
            echo -e "\nNo domains found in toplist."
            return
        fi

        if "$unattended"; then
            echo "Domains in toplist:"
            sleep 0.3
            cat in_toplist.tmp
            exit 1
        fi

        numbered_toplist=$(cat in_toplist.tmp | awk '{print NR ". " $0}')

        echo -e "\nTOPLIST MENU"
        sleep 0.3
        echo "$numbered_toplist"
        echo "*. Blacklist/whitelist the domain"
        echo "e. Edit lists"
        echo "r. Run filter again"
        read -r choice

        if [[ "$choice" == 'e' ]]; then
            echo -e "\nEnter 'x' to go back to the previous menu."
            source "$edit_script"
            continue 
        elif [[ "$choice" == 'r' ]]; then   
            echo -e "\nRunning filter again..."
            cp "${pending_file}.bak" "$pending_file"
            filter_pending
            exit 0
        elif ! [[ "$choice" =~ ^[0-9]+$ ]]; then
            echo -e "\nInvalid option."
            continue
        fi

        chosen_domain=$(echo "$numbered_toplist" \
           | awk -v n="$choice" '$1 == n {print $2}')
        echo -e "\nDomain: ${chosen_domain}"
        sleep 0.3
        echo "Choose a list to add to:"
        echo "b. Blacklist"
        echo "w. Whitelist"
        read -r choice

        if [[ "$choice" == 'b' ]]; then
            echo "$chosen_domain" >> "$blacklist_file"
            sort -u "$blacklist_file" -o "$blacklist_file"
            echo -e "\nBlacklisted: ${chosen_domain}"
            echo
        elif [[ "$choice" == 'w' ]]; then
            echo "$chosen_domain" >> "$whitelist_file"
            sort -u "$whitelist_file" -o "$whitelist_file"
            echo -e "\nWhitelisted: ${chosen_domain}"
            echo "Run the filtering again to apply changes."
        else
            echo -e "\nInvalid option."
        fi
    done
}

function filter_pending {
    sleep 0.5
    
    cp "$pending_file" "${pending_file}.bak"

    sort -u "$pending_file" -o "$pending_file"

    echo -e "\nTotal domains retrieved/pending: $(wc -l < ${pending_file})"

    # Remove domains already in the blocklist
    comm -23 "$pending_file" "$raw_file" > 1.tmp

    comm -23 1.tmp "$dead_domains_file" > 2.tmp

    sleep 0.5
    echo -e "\nFiltering log:"

    grep -Ff "$whitelist_file" 2.tmp | grep -vxFf "$blacklist_file" > whitelisted.tmp \
        && cat whitelisted.tmp | awk '{print $0 " (whitelisted)"}'
    comm -23 2.tmp whitelisted.tmp > 3.tmp

    grep -E '\.(gov|edu)(\.[a-z]{2})?$' 3.tmp | awk '{print $0 " (TLD)"}' \
        && grep -vE '\.(gov|edu)(\.[a-z]{2})?$' 3.tmp > 4.tmp \
        || mv 3.tmp 4.tmp

    # This regex matches valid domains. This includes puny code TLDs (.xn--*)
    grep -vE '^[[:alnum:].-]+\.[[:alnum:]-]{2,}$' 4.tmp | awk '{print $0 " (invalid)"}' \
        && grep -E '^[[:alnum:].-]+\.[[:alnum:]-]{2,}$' 4.tmp > 5.tmp \
        || mv 4.tmp 5.tmp

    > redundant.tmp
    while read -r entry; do
        grep "\.${entry}$" 5.tmp >> redundant.tmp
    done < "$optimised_entries"

    grep -vxFf redundant.tmp 5.tmp > 6.tmp
    "$debug" && cat redundant.tmp | awk '{print $0 " (redundant)"}'

    export debug="$debug"
    > dead.tmp
    cat 6.tmp | xargs -I{} -P6 bash -c '
        domain="$1"
        if dig @1.1.1.1 "$domain" | grep -Fq "NXDOMAIN"; then
            echo "$domain" >> dead.tmp
            "$debug" && echo "$domain (dead)"
        fi
    ' -- {}

    # It appears that the dead file isn't always sorted
    grep -vxFf dead.tmp 6.tmp > 7.tmp

    mv 7.tmp "$pending_file"

    if ! [[ -s "$pending_file" ]]; then
        echo -e "\nNo pending domains."
        exit 0
    fi

    echo -e "\nPending domains not in blocklist: $(wc -l < ${pending_file})"
    sleep 0.3
    echo "Domains:"
    cat "$pending_file"

    check_toplist
}

function optimise_blocklist {
    while true; do
        sleep 0.5

        grep -E '\..*\.' "$raw_file" \
            | cut -d '.' -f2- \
            | awk -F '.' '$1 ~ /.{4,}/ {print}' \
            | sort \
            | uniq -d > 1.tmp
    
        comm -23 1.tmp "$optimiser_whitelist" > 2.tmp
        comm -23 2.tmp "$optimised_entries" > domains.tmp
    
        [[ -s domains.tmp ]] || return

        numbered_domains=$(cat domains.tmp | awk '{print NR ". " $0}')

        echo -e "\nOPTIMISER MENU"
        sleep 0.3
        echo "Potential optimised entries:"
        echo "$numbered_domains"
        echo "*. Whitelist the entry"
        echo "a. Add all optimised entries"
        read -r choice

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            chosen_domain=$(echo "$numbered_domains" \
                | awk -v n="$choice" '$1 == n {print $2}')
            echo -e "\nWhitelisted: ${chosen_domain}"
            echo "$chosen_domain" >> "$optimiser_whitelist"
            sort "$optimiser_whitelist" -o "$optimiser_whitelist"
            continue
        elif ! [[ "$choice" == 'a' ]]; then
            echo -e "\nInvalid option."
            continue
        fi

        echo -e "\nAdding optimised entries..."
        cat domains.tmp >> "$raw_file"
        cat domains.tmp >> "$optimised_entries"
        sort -u "$raw_file" -o "$raw_file"
        sort "$optimised_entries" -o "$optimised_entries"

        sleep 0.3
        echo "Removing redundant entries..."
        while read -r entry; do
            grep "\.${entry}$" "$raw_file" >> redundant.tmp
        done < domains.tmp
        grep -vxFf redundant.tmp "$raw_file" > raw.tmp
        mv raw.tmp "$raw_file"
            
        sleep 0.3
        echo "Merging..."

        sleep 0.3
        return
    done
}

function merge_pending {
    echo -e "\nMerging with blocklist..."

    cp "$raw_file" "${raw_file}.bak"

    num_before=$(wc -l < "$raw_file")

    cat "$pending_file" >> "$raw_file" 

    sort -u "$raw_file" -o "$raw_file"

    "$unattended" && sleep 0.5 || optimise_blocklist

    num_after=$(wc -l < "$raw_file")
    
    num_added=$((num_after - num_before))

    echo -e "\nTotal domains before: $num_before"
    echo "Total domains added: $num_added"
    echo "Total domains after: $num_after"

    > "$pending_file"
    
    if "$unattended"; then
        commit_msg='Automatic domain retrieval'
        
        previous_count=$(sed -n '10p' "$stats_file")
        new_count=$((previous_count + num_added))
        sed -i "10s/.*/${new_count}/" "$stats_file"

        sleep 0.5
    else
        sleep 0.5
        read -rp $'\nDo you want to push the blocklist? (Y/n): ' answer
        if [[ "$answer" =~ ^[Yy]$ || -z "$answer" ]]; then
            commit_msg="Manual domain retrieval"
        else
            exit 0
        fi
    fi

    echo 

    # Push white/black lists too for when they are modified through the editing script
    git add "$raw_file" "$stats_file" "$whitelist_file" "$blacklist_file" \
        "$optimised_entries" "$optimiser_whitelist"
    git commit -m "$commit_msg"
    git push -q

    exit 0
}

if "$unattended"; then
    echo -e "\nRetrieving domains..."
else
    echo -e "\nRemember to pull the latest changes beforehand!" 
fi

sleep 0.5

"$use_pending_only" || retrieve_domains

filter_pending

"$unattended" && merge_pending

while true; do
    echo -e "\nPENDING DOMAINS MENU"
    sleep 0.3
    echo "m. Merge with blocklist"
    echo "e. Edit lists"
    echo "r. Run filter again"
    echo "x. Save pending and exit"
    read -r choice
    case "$choice" in
        m)
            merge_pending
            ;;
        e)
            echo -e "\nEnter 'x' to go back to the previous menu."
            source "$edit_script"
            ;;
        r)
            echo -e "\nRunning filter again..."
            cp "${pending_file}.bak" "$pending_file"
            filter_pending
            exit 0
            ;;
        x)
            exit 0 ;;
        *)
            echo -e "\nInvalid option." ;;
    esac
done

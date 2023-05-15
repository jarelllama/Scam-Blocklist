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
            echo "Invalid option: -$OPTARG" ;;
        :)
            echo "Option -$OPTARG requires an argument" ;;
    esac
done

if [[ -s "$pending_file" && ! "$use_pending_only" ]]; then
    read -rp $'\nEmpty the pending file? (Y/n): ' answer
    [[ "$answer" =~ ^[Yy]? ]] && > "$pending_file"
fi

if ! "$unattended"; then
    echo -e "\nRemember to pull the latest changes beforehand!"
    sleep 0.5
fi

function retrieve_domains {
    echo -e "\nRetrieving domains...\n"
    echo "Search filter: $time_filter"
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

        while read -r subdomain; do
            sed -i "s/^${subdomain}\.//" domains.tmp
        done < "$subdomains_file"
        sort -u domains.tmp -o domains.tmp

        cat domains.tmp >> "$pending_file"

        echo "Domains retrieved: $(wc -l < domains.tmp)"
        echo "--------------------------------------"
    done < "$search_terms_file"

    if ! [[ -s "$pending_file" ]]; then
        echo -e "\nNo retrieved domains. Try changing VPN servers."
        exit 1
    fi
}

function filter_pending {
    tr '[:upper:]' '[:lower:]' < "$pending_file" > 1.tmp

    sort -u 1.tmp -o 1.tmp

    cp 1.tmp "${pending_file}.bak"

    sleep 0.5
    echo -e "\nTotal domains retrieved/pending: $(wc -l < 1.tmp)"

    sleep 0.3
    echo -e "\nFiltering..."

    # Remove domains already in the blocklist
    comm -23 1.tmp "$raw_file" > 2.tmp

    comm -23 2.tmp "$dead_domains_file" > 3.tmp

    sleep 0.3
    echo -e "\nFiltering log:"

    grep -Ff "$whitelist_file" 3.tmp | grep -vxFf "$blacklist_file" > whitelisted.tmp
    cat whitelisted.tmp | awk '{print $0 " (whitelisted)"}'
    comm -23 3.tmp whitelisted.tmp > 4.tmp

    grep -E '\.(gov|edu)(\.[a-z]{2})?$' 4.tmp | awk '{print $0 " (TLD)"}'
    grep -vE '\.(gov|edu)(\.[a-z]{2})?$' 4.tmp > 5.tmp

    # This regex matches valid domains. This includes puny code TLDs (.xn--*)
    grep -vE '^[[:alnum:].-]+\.[[:alnum:]-]{2,}$' 5.tmp | awk '{print $0 " (invalid)"}'
    grep -E '^[[:alnum:].-]+\.[[:alnum:]-]{2,}$' 5.tmp > 6.tmp

    > redundant.tmp
    while read -r entry; do
        grep "\.${entry}$" 6.tmp >> redundant.tmp
    done < "$optimised_entries"

    "$debug" && cat redundant.tmp | awk '{print $0 " (redundant)"}'
    grep -vxFf redundant.tmp 6.tmp > 7.tmp

    export debug="$debug"
    > dead.tmp
    cat 7.tmp | xargs -I{} -P6 bash -c '
        domain="$1"
        if dig @1.1.1.1 "$domain" | grep -Fq "NXDOMAIN"; then
            echo "$domain" >> dead.tmp
            "$debug" && echo "$domain (dead)"
        fi
    ' -- {}

    # It appears that the dead file isn't always sorted
    grep -vxFf dead.tmp 7.tmp > 8.tmp

    mv 8.tmp "$pending_file"

    if ! [[ -s "$pending_file" ]]; then
        echo -e "\nNo pending domains."
        exit 0
    fi

    echo -e "\nPending domains not in blocklist: $(wc -l < ${pending_file})"
    sleep 0.5
    echo "Domains:"
    cat "$pending_file"

    sleep 0.5
    check_toplist
}

function check_toplist {
    while true; do
        comm -12 "$pending_file" "$toplist_file" \
            | grep -vxFf "$blacklist_file" > in_toplist.tmp

        if ! [[ -s in_toplist.tmp ]]; then
            echo -e "\nNo domains found in toplist."
            return
        fi

        if "$unattended"; then
            echo "Domains in toplist:"
            cat in_toplist.tmp
            echo -e "\nExiting..."
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
            sort "$blacklist_file" -o "$blacklist_file"
            echo -e "\nBlacklisted: ${chosen_domain}"
            echo
        elif [[ "$choice" == 'w' ]]; then
            echo "$chosen_domain" >> "$whitelist_file"
            sort "$whitelist_file" -o "$whitelist_file"
            echo -e "\nWhitelisted: ${chosen_domain}"
            echo "Run the filtering again to apply whitelist change."
        else
            echo -e "\nInvalid option."
        fi
        sleep 0.5
    done
}

function optimise_blocklist {
    while true; do
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
        sleep 0.2
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

        sleep 0.5
            
        echo "Removing redundant entries..."
        while read -r entry; do
            grep "\.${entry}$" "$raw_file" >> redundant.tmp
        done < domains.tmp
        grep -vxFf redundant.tmp "$raw_file" > raw.tmp
        mv raw.tmp "$raw_file"
            
        sleep 0.5
            
        echo "Merging..."
        return
    done
}

function merge_pending {
    cp "$raw_file" "${raw_file}.bak"

    num_before=$(wc -l < "$raw_file")

    cat "$pending_file" >> "$raw_file" 

    sort -u "$raw_file" -o "$raw_file"

    "$unattended" || optimise_blocklist

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
    else
        read -rp $'\nDo you want to push the blocklist? (Y/n): ' answer
        if [[ "$answer" =~ ^[Yy]$ ]] || [[ -z "$answer" ]]; then
            commit_msg="Manual domain retrieval"
        else
            exit 0
        fi
    fi

    echo -e "\nPushing changes...\n"
    sleep 0.5

    # Push white/black lists too for when they are modified through the editing script
    git add "$raw_file" "$stats_file" "$whitelist_file" "$blacklist_file" \
        "$optimised_entries" "$optimiser_whitelist"
    git commit -m "$commit_msg"
    git push -q

    exit 0
}

"$use_pending_only" || retrieve_domains

filter_pending

if "$unattended"; then
    echo -e "\nMerging with blocklist..."
    sleep 0.5
    merge_pending
fi

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
            if [[ -s in_toplist.tmp ]]; then
                echo -e "\nDomains found in the toplist. Not merging."
                continue
            fi
            echo -e "\nMerging with blocklist..."
            sleep 0.5
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
            ;;
        x)
            exit 0
            ;;
        *)
            echo -e "\nInvalid option."
            ;;
    esac
done

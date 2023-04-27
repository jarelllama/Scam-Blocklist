#!/bin/bash

readme="README.md"
template="data/README.md"
count_history="data/count_history.txt"
raw_file="data/raw.txt"
domains_file="domains.txt"
adblock_file="adblock.txt"
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"

adblock_count=$(grep -vE '^(!|$)' "$adblock_file" | wc -l)

domains_count=$(grep -vE '^(#|$)' "$domains_file" | wc -l)

sed -i 's/adblock_count/'"$adblock_count"'/g' "$template"

sed -i 's/domains_count/'"$domains_count"'/g' "$template"

todays_date=$(date -u +"%m%d%y")

date_in_file=$(head -n 1 "$count_history")

if [[ "$todays_date" != "$date_in_file" ]]; then
    count_before=$(tail -n 1 "$count_history")

    count_diff=$((adblock_count - count_before))

    sed -i 's/found_yest/'"$diff"'/g' "$template"

    > "$count_history"

    echo "$todays_date" >> "$count_history"

    echo "$adblock_count" >> "$count_history"
fi

top_tlds=$(awk -F '.' '{print $NF}' "$raw_file" | sort | uniq -c | sort -nr | head -10 | awk '{print "| " $2, " | "$1 " |"}')

awk -v var="$top_tlds" '{gsub(/top_tlds/,var)}1' "$template" > template.tmp

if ! diff -q "$readme" template.tmp >/dev/null; then
    sed -i 's/update_time/'"$(date -u +"%a %b %d %H:%M UTC")"'/g' template.tmp
fi

cp template.tmp "$readme"

git config user.email "$github_email"
git config user.name "$github_name"

git add "$domains_file" "$adblock_file"
git commit -m "Build lists"

git add "$readme"
git commit -m "Update README count"

git push

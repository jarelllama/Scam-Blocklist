#!/bin/bash

domains_file="domains.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"
toplist_file="toplist.txt"
tlds_file="white_tlds.txt"

# Backup the domains file before making any changes
cp "$domains_file" "$domains_file.bak"

# Create temporary file
touch tmp1.txt

# Count the number of domains before filtering
num_before=$(wc -l < "$domains_file")

# Remove www subdomains
sed -i 's/^www\.//' "$domains_file"

# Remove duplicates and sort alphabetically
sort -u -o "$domains_file" "$domains_file"

echo "Domains removed:"

# Print and remove non domain entries
awk '{ if ($0 ~ /^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$/) print $0 > "tmp1.txt"; else print $0" (invalid)" }' "$domains_file"

# Print whitelisted domains
grep -f "$whitelist_file" -i tmp1.txt | awk '{print $1" (whitelisted)"}'

# Remove whitelisted domains
awk -v FS=" " 'FNR==NR{a[tolower($1)]++; next} !a[tolower($1)]' "$whitelist_file" tmp1.txt | grep -vf "$whitelist_file" -i | awk -v FS=" " '{print $1}' > tmp2.txt

# Print domains with whitelisted TLDs
grep -oE "(\S+)\.($(paste -sd '|' "$tlds_file"))$" tmp2.txt | sed "s/\(.*\)/\1 (TLD)/"

# Remove domains with whitelisted TLDs
grep -vE "\.($(paste -sd '|' "$tlds_file"))$" tmp2.txt > tmp3.txt

# Create temporary file for dead domains
touch tmp_dead.txt

# Find and print dead domains
cat tmp3.txt | xargs -I{} -P10 bash -c "
  if dig @1.1.1.1 {} | grep -q 'NXDOMAIN'; then
    echo {} >> tmp_dead.txt
    echo '{} (dead)'
  fi
"

# Remove dead domains
grep -vFf tmp_dead.txt tmp3.txt > tmp4.txt

# Save changes to the domains file
mv tmp4.txt "$domains_file"

# Print domains found in the toplist
echo -e "\nDomains in toplist:"
grep -xFf "$domains_file" "$toplist_file" | grep -vxFf "$blacklist_file"

# Count the number of domains after filtering
num_after=$(wc -l < "$domains_file")

# Remove temporary files
rm tmp*.txt

# Print counters
echo "Total domains before: $num_before"
echo "Total domains removed: $((num_before - num_after))"
echo "Final domains after: $num_after"

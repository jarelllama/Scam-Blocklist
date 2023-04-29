pending_file=b
subdomains_file=a

touch all_entries_with_subdomains.tmp
touch all_entries_no_subdomains.tmp

while read -r subdomain; do
        grep "^$subdomain" "$pending_file" > entries_with_subdomains.tmp
        
        cat entries_with_subdomains.tmp >> all_entries_with_subdomains.tmp
        
        awk -v subdomain="$subdomain" '{sub("^"subdomain"\\.", ""); print}' entries_with_subdomains.tmp > entries_no_subdomains.tmp
    
        cat entries_no_subdomains.tmp >> all_entries_no_subdomains.tmp
    done < "$subdomains_file"
   
    grep -vxFf all_entries_with_subdomains.tmp "$pending_file" > pending_no_subdomains.tmp
    
    cat all_entries_no_subdomains.tmp >> pending_no_subdomains.tmp
    
    sort -u pending_no_subdomains.tmp -o unique_sites.tmp

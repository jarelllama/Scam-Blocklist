#!/bin/bash

domains_file="domains.txt"
whitelist_file="whitelist.txt"
blacklist_file="blacklist.txt"

echo "Choose which list to add to:"
echo "1. Whitelist"
echo "2. Blacklist"
echo "3. Blocklist"
read list_choice

read -p "Enter the new entry: " new_entry
new_entry="${new_entry,,}

case $list_choice in
  1)
    echo $entry >> $whitelist_file
    sort -o $whitelist_file $whitelist_file
    ;;
  2)
    echo $entry >> $blacklist_file
    sort -o $blacklist_file $blacklist_file
    ;;
  3)
    echo $entry >> $domains_file
    sort -o $domains_file $domains_file
    ;;
  *)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac

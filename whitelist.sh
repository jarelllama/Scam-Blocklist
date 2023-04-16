#!/bin/bash

whitelist_file="whitelist.txt"

read -p "Enter the new entry: " new_entry
new_entry="${new_entry,,}"

echo "$new_entry" >> "$whitelist_file"

sort -o "$whitelist_file" "$whitelist_file"

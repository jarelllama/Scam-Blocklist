#!/bin/bash

whitelist_file="whitelist.txt"

read -rp "Enter the new entry: " new_entry
new_entry="${new_entry,,}"

echo "$new_entry" >> "$whitelist_file"

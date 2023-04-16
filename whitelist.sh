#!/bin/bash

whitelist_file="whitelist.txt"

# Prompt user to enter a new entry to the whitelist
read -p "Enter a new entry : " new_entry
new_entry=$(echo "${new_entry}" | tr '[:upper:]' '[:lower:]')

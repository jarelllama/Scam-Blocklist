#!/bin/bash

new_domains_file="new_domains.txt"

if [[ -s $new_domains_file ]]; then
  read -p "The new domains file is not empty. Do you want to empty it? (y/N) " answer

  if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo "" > "$new_domains_file"
  fi
fi

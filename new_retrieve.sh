#!/bin/bash

# Define input and output file locations
new_domains_file="new_domains.txt"
search_terms_file="search_terms.txt"

# If new_domains_file is not empty, prompt the user whether to empty it or not.
if [ -s "$new_domains_file" ]
then
    read -p "new_domains_file is not empty. Do you want to empty it? (y/n)" answer
    if [ "$answer" == "y" ]
    then
        > $new_domains_file                              fi
fi

#!/bin/bash

template="data/README.md.template"
readme="README.md"

cp "$template" "$readme"

git config user.email "$github_email"
git config user.name "$github_name"

git add "$readme"
git commit -qm "Update README"
git push -q

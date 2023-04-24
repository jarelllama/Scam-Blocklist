#!/bin/bash
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"
git config user.email "$github_email"
git config user.name "$github_name"
git add temp.txt
git commit -qm "Test commit"
git push -q

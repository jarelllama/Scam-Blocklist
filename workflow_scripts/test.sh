#!/bin/bash
github_email="91372088+jarelllama@users.noreply.github.com"
github_name="jarelllama"
git config user.email "$github_email"
git config user.name "$github_name"
git add test.txt
git commit -q -m "Test commit"
git push -f -q

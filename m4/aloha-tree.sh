#!/bin/bash
set -u
curl -sL -m 60 "https://api.github.com/repos/Project-Aloha/mu_aloha_platforms/git/trees/main?recursive=1" -o /tmp/aloha-tree.json
echo "size=$(wc -c < /tmp/aloha-tree.json)"
grep -o '"path": "[^"]*"' /tmp/aloha-tree.json | grep -iE 'judyp|mh2lm|flashlm|/LG/' | head -40
echo "== LG dirs =="
grep -o '"path": "Platforms/[^"]*"' /tmp/aloha-tree.json | head -60

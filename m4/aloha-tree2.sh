#!/bin/bash
set -u
if [ ! -s /tmp/aloha-tree.json ]; then
  curl -sL -m 60 "https://api.github.com/repos/Project-Aloha/mu_aloha_platforms/git/trees/main?recursive=1" -o /tmp/aloha-tree.json
fi
echo "== Platforms 一级目录 =="
grep -o '"path": "Platforms/[^/"]*"' /tmp/aloha-tree.json | sed 's/.*Platforms\///; s/"//' | sort -u
echo "== 任何 LG 相关 =="
grep -o '"path": "[^"]*"' /tmp/aloha-tree.json | grep -iE 'lg|v35|judy|845' | head -30

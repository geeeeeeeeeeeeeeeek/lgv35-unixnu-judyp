#!/bin/bash
set -u
for r in drx1x2/UniXNU-flashlm cocopaim15/UniXNU-alphaplus; do
  echo "== $r"
  curl -sL -m 25 "https://api.github.com/repos/$r/contents/" \
    | grep -E '"name"|"type"' | head -50
  echo
done

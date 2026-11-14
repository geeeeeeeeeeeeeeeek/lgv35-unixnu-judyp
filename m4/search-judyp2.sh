#!/bin/bash
set -u
q() {
  echo "== query: $1"
  curl -sL -m 25 "https://api.github.com/search/repositories?q=$1&per_page=6" \
    | grep -E 'full_name|description' | sed 's/^ *//' | head -14
  echo
}
q "judyp+uefi"
q "judypn+uefi"
q "aloha+platforms+qualcomm"
q "lg+judyp"

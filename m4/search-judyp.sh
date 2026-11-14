#!/bin/bash
set -u
q() {
  echo "== $1"
  curl -sL -m 25 "https://api.github.com/search/repositories?q=$2&per_page=8" \
    | grep -E '"full_name"|"description"|"updated_at"' | head -24
  echo
}
q "judyp" "judyp"
q "lg-judyp" "lg-judyp"
q "aloha platforms" "mu_aloha_platforms"
q "project aloha uefi" "aloha+uefi+qualcomm"

#!/bin/bash
set -u
mkdir -p /tmp/lgrefs
fetch() {
  repo="$1"; path="$2"; out="$3"
  curl -sL -m 30 -H "Accept: application/vnd.github.raw" \
    "https://api.github.com/repos/$repo/contents/$path" -o "/tmp/lgrefs/$out"
  echo "--- $repo/$path -> $out ($(wc -c < /tmp/lgrefs/$out) bytes)"
}
fetch cocopaim15/UniXNU-alphaplus NOTES-mh2lm.md alphaplus-NOTES-mh2lm.md
fetch cocopaim15/UniXNU-alphaplus DEVIATIONS.md alphaplus-DEVIATIONS.md
fetch cocopaim15/UniXNU-alphaplus board.toml alphaplus-board.toml
fetch drx1x2/UniXNU-flashlm DEVIATIONS.md flashlm-DEVIATIONS.md
fetch drx1x2/UniXNU-flashlm NOTES.md flashlm-NOTES.md
fetch drx1x2/UniXNU-flashlm board.toml flashlm-board.toml
fetch drx1x2/UniXNU-flashlm HANDOVER.md flashlm-HANDOVER.md

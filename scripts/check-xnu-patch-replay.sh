#!/bin/bash
# Replay the complete XNU patch series exactly like build-xnu-4k-baseline.sh does, on a real
# checkout of the locked XNU revision.  Two CI failures in a row came from patches that applied
# forwards but could not be reversed on the already-patched tree (the build script replays every
# patch backwards before the second pass), so this gate is mandatory before dispatching CI.
#
#   pass 1: apply all patches in filename order to a pristine tree
#   pass 2: undo the five LATE hooks, then for each patch reverse-check, else forward-apply
#   pass 3: reverse everything newest-first, then apply everything forwards again
#
# Usage: bash scripts/check-xnu-patch-replay.sh
# Env:   UNIXNU=<UniXNU checkout>   XNU_CACHE=<tarball cache>   JOBS=<unused>
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
UNIXNU=${UNIXNU:-$ROOT/../UniXNU}
CACHE=${XNU_CACHE:-$HOME/.cache/unixnu-xnu-replay}
REV=$(awk '/^\[source\."xnu"\]/{f=1} f && /^commit/{gsub(/[",]/," "); print $3; exit}' "$ROOT/unixnu.lock")
SER=$CACHE/series
TREE=$CACHE/tree
FAILS=0

[ -n "$REV" ] || { echo "cannot read xnu commit from unixnu.lock"; exit 2; }
[ -d "$UNIXNU/patches/xnu" ] || { echo "no shared patches in $UNIXNU"; exit 2; }
mkdir -p "$CACHE"

if [ ! -f "$CACHE/xnu.tar.gz" ]; then
  echo "fetching xnu $REV ..."
  export https_proxy=${https_proxy:-} http_proxy=${http_proxy:-}
  curl -L --retry 3 -m 1800 -o "$CACHE/xnu.tar.gz.part" \
    "https://codeload.github.com/apple-oss-distributions/xnu/tar.gz/$REV" || exit 2
  mv "$CACHE/xnu.tar.gz.part" "$CACHE/xnu.tar.gz"
fi
if [ ! -d "$CACHE/xnu-src/bsd" ]; then
  rm -rf "$CACHE/xnu-src"
  mkdir -p "$CACHE/xnu-src"
  tar xzf "$CACHE/xnu.tar.gz" -C "$CACHE/xnu-src" --strip-components=1 || exit 2
fi

rm -rf "$SER" "$TREE"
mkdir -p "$SER"
cp "$UNIXNU"/patches/xnu/*.patch "$SER"/
cp "$ROOT"/patches/xnu-device/*.patch "$SER"/
echo "series: $(ls "$SER"/*.patch | wc -l) patches"
cp -a "$CACHE/xnu-src" "$TREE"
cd "$TREE" || exit 2
git init -q .; git add -A >/dev/null; git -c user.email=a@b -c user.name=g commit -qm base

echo "== pass 1: forward =="
for p in $(ls "$SER"/*.patch | sort); do
  if ! git apply --check "$p" 2>/tmp/xnu-gate.err; then
    echo "FAIL forward $(basename "$p"): $(head -2 /tmp/xnu-gate.err | tr '\n' ' ')"
    FAILS=$((FAILS+1))
  else
    git apply "$p" || { echo "FAIL apply $(basename "$p")"; FAILS=$((FAILS+1)); }
  fi
done

echo "== pass 2: CI replay (reverse-check, else forward) =="
for L in zzz-boot-progress.patch zzyb-native-cryptex-os-view.patch zzy-staged-system-apps.patch \
         zzy-native-gpu-addon-mount.patch zzyc-owner-skip-launch-constraints.patch; do
  if [ -f "$SER/$L" ] && git apply --reverse --check "$SER/$L" >/dev/null 2>&1; then
    git apply --reverse "$SER/$L"
  fi
done
for p in $(ls "$SER"/*.patch | sort); do
  git apply --reverse --check "$p" >/dev/null 2>&1 && continue
  if git apply --check "$p" >/dev/null 2>&1; then
    git apply "$p"
  else
    echo "FAIL replay $(basename "$p")"
    FAILS=$((FAILS+1))
  fi
done

echo "== pass 3: reverse all, then forward all =="
for p in $(ls "$SER"/*.patch | sort -r); do
  if git apply --reverse --check "$p" >/dev/null 2>&1; then
    git apply --reverse "$p"
  else
    echo "FAIL reverse $(basename "$p")"
    FAILS=$((FAILS+1))
  fi
done
for p in $(ls "$SER"/*.patch | sort); do
  if git apply --check "$p" >/dev/null 2>&1; then
    git apply "$p"
  else
    echo "FAIL reapply $(basename "$p")"
    FAILS=$((FAILS+1))
  fi
done

echo "failures=$FAILS"

# static cross-check: the expected checkpoint marks must survive the final pass
MARK_FAILS=0
for m in 'BC37 lockdown returned' 'BC38 vm_set_restrictions done' 'BC39 kperf early done' 'BC44 enter bsd_init' 'BC36 StartIOKitMatching end' 'BC50 DTAlloc enter'; do
  if ! grep -rqF "$m" --include='*.c' --include='*.cpp' .; then
    echo "MARK MISSING: $m"
    MARK_FAILS=$((MARK_FAILS+1))
  fi
done
grep -qF 'boot_progress_stage("bsd_init: " x)' bsd/kern/bsd_init.c || {
  echo "MARK MISSING: bsd_init_kprintf -> boot_progress_stage"; MARK_FAILS=$((MARK_FAILS+1)); }
# C sources cannot carry the C++-only weak_import attribute; boot_progress.h already declares it.
if grep -rn 'weak_import' osfmk/kern/startup.c bsd/kern/bsd_init.c >/dev/null 2>&1; then
  echo "MARK INVALID: weak_import in a C source"; MARK_FAILS=$((MARK_FAILS+1)); fi
grep -qF '#define UNI_BC(text) do { boot_progress_stage(text);' osfmk/kern/startup.c || {
  echo "MARK MISSING: startup.c UNI_BC"; MARK_FAILS=$((MARK_FAILS+1)); }
echo "MARK_FAILURES=$MARK_FAILS"

TOTAL=$((FAILS+MARK_FAILS))
echo "TOTAL_FAILURES=$TOTAL"
exit $([ "$TOTAL" -eq 0 ] && echo 0 || echo 1)


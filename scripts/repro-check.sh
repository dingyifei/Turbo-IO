#!/bin/bash
set -euo pipefail
umask 077
# never installs to a device, never signs
# Builds the phone addon (and, with --apple-ai, TurboAppleAI) twice from one
# commit (HEAD, or --rev) and compares the unsigned dylibs byte for byte:
#   a: a `git archive` export (no git; the build commit comes from BUILD_COMMIT)
#   b: a detached `git worktree` checkout at a path of a different length
# Both builds go through `turbo-package.sh --build-only`, so they use the package
# flag sets. Uncommitted changes are not part of either build.
REPO=$(cd "$(dirname "$0")/.." && pwd)
TURBO_INPUTS=${TURBO_INPUTS:-"$HOME/projects/personal/turboio-inputs"}
usage='Usage: repro-check.sh [--apple-ai] [--host 1021|1021-full] [--release cN] [--wire-log] [--rev <commit>] [--keep]'
pkg_args=()
apple_ai=0
keep=0
host=1021-full
rev=HEAD
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apple-ai) apple_ai=1; shift ;;
    --host) [[ ${2:-} == 1021 || ${2:-} == 1021-full ]] || { echo "$usage" >&2; exit 2; }; host=$2; shift 2 ;;
    --release) [[ ${2:-} =~ ^c[0-9]+$ ]] || { echo "$usage" >&2; exit 2; }; pkg_args+=(--release "$2"); shift 2 ;;
    --wire-log) pkg_args+=(--wire-log); shift ;;
    --keep) keep=1; shift ;;
    --rev) [[ -n ${2:-} ]] || { echo "$usage" >&2; exit 2; }; rev=$2; shift 2 ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
done
pkg_args+=(--host "$host")
cd "$REPO"
rev=$(git rev-parse --verify "$rev^{commit}")
[[ -z $(git status --porcelain --untracked-files=no) ]] || echo "note: uncommitted changes are not checked; building ${rev:0:12}" >&2
# The private bootstrap sources are gitignored, so neither tree has them. Both get
# them the way the gate's private stage does: from the private backup, after its
# SHA-256 check.
backup=$TURBO_INPUTS/private-backup/ios107
(cd "$backup" && shasum -a 256 -c SHA256SUMS) >/dev/null || { echo 'REPRO FAIL: private backup missing or does not match its SHA256SUMS' >&2; exit 1; }
work=$(mktemp -d "${TMPDIR:-/tmp}/turbo-repro.XXXXXX")
work=$(cd "$work" && pwd -P)
a=$work/a
b=$work/second-checkout-at-a-longer-path/b
cleanup() {
  git -C "$REPO" worktree remove --force "$b" >/dev/null 2>&1 || true
  git -C "$REPO" worktree prune >/dev/null 2>&1 || true
  if [[ $keep == 1 ]]; then echo "kept $work" >&2; else rm -rf "$work"; fi
}
trap cleanup EXIT
mkdir -p "$a" "$(dirname "$b")"
git archive "$rev" | tar -x -C "$a"
git worktree add --quiet --detach "$b" "$rev"
for side in a b; do
  dir=${!side}
  for file in PrivateBootstrap.h PrivateBootstrap.m; do
    cp -p "$backup/$file" "$dir/ios-addon/$file"
  done
  extra=()
  [[ $apple_ai != 1 ]] || extra=(--apple-ai "$work/ai-$side")
  (cd "$dir" && TURBO_INPUTS=$TURBO_INPUTS bash scripts/turbo-package.sh ${extra[@]+"${extra[@]}"} "${pkg_args[@]}" --build-only "repro-check-$side") >"$work/build-$side.log" 2>&1 \
    || { echo "REPRO FAIL: build $side (see $work/build-$side.log)" >&2; keep=1; exit 1; }
  # Copied out, so --keep still has both after the worktree is removed.
  mkdir "$work/addon-$side"
  cp -p "$dir/ios-addon/build/mapkit/TurboIOPrivateAddon.dylib" "$work/addon-$side/"
done
pairs=("$work/addon-a/TurboIOPrivateAddon.dylib" "$work/addon-b/TurboIOPrivateAddon.dylib")
[[ $apple_ai != 1 ]] || pairs+=("$work/ai-a/TurboAppleAI.dylib" "$work/ai-b/TurboAppleAI.dylib")
status=0
for ((i=0; i<${#pairs[@]}; i+=2)); do
  x=${pairs[i]} y=${pairs[i+1]}
  name=$(basename "$x")
  if cmp -s "$x" "$y"; then
    printf 'same %s %s\n' "$(shasum -a 256 "$x" | cut -d' ' -f1)" "$name"
  else
    printf 'DIFFERENT %s: %s vs %s\n' "$name" "$(shasum -a 256 "$x" | cut -d' ' -f1)" "$(shasum -a 256 "$y" | cut -d' ' -f1)" >&2
    status=1
  fi
done
printf 'commit %s host %s toolchain %s, iphoneos SDK %s\n' "${rev:0:12}" "$host" \
  "$(xcodebuild -version 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')" "$(xcrun --sdk iphoneos --show-sdk-build-version)"
if [[ $status != 0 ]]; then keep=1; echo 'REPRO FAIL' >&2; exit 1; fi
echo 'REPRO PASS'

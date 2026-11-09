#!/bin/bash
# Fails when the addon carries the wire log recorder (TIO_WIRE_LOG=1). The gate runs it
# on the default build and turbo-package.sh on any build made without --wire-log.
# nm's output is read into a variable first: `nm | grep -q` under pipefail reports the
# SIGPIPE nm gets when grep stops at the first match, so a match would read as a pass.
set -euo pipefail
[[ $# == 1 && -f $1 ]] || { echo 'Usage: wirelog-absent.sh <dylib>' >&2; exit 2; }
symbols=$(nm "$1")
if grep -q 'WireLog' <<<"$symbols"; then echo 'Unexpected wire log symbol in a build without the wire log' >&2; exit 1; fi
if grep -aFq 'turbo-wirelog' "$1"; then echo 'Unexpected wire log string in a build without the wire log' >&2; exit 1; fi
echo 'no wire log'

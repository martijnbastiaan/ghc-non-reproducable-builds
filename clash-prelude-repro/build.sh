#!/bin/bash
# usage: build.sh <ghc> <mode: make|oneshot> <outdir> [extra ghc flags]
#   make    : extra flags should contain -jN
#   oneshot : compiles modules one by one in the order listed in order.txt
set -u
D=$(cd "$(dirname "$0")" && pwd)
GHC=$1; MODE=$2; OUT=$3; shift 3
mkdir -p "$OUT"
export TMPDIR=/home/martijn/code/ghc-non-reproducable-builds/.tmp
mapfile -t FLAGS < "$D/flags.txt"
COMMON=("${FLAGS[@]}" -i -i"$D/src" -i"$D/autogen" -optP-include -optP"$D/cabal_macros.h"
        -outputdir "$OUT" -odir "$OUT" -hidir "$OUT" -stubdir "$OUT" -this-unit-id clash-prelude-1.11.0-inplace)
if [ "$MODE" = make ]; then
  mapfile -t MODS < "$D/modules.txt"
  "$GHC" --make "${COMMON[@]}" "$@" "${MODS[@]}" > "$OUT/log" 2>&1 || { echo "FAIL $OUT"; exit 1; }
else
  while read -r m; do
    case "$m" in *"[boot]") ext=hs-boot; m=${m%"[boot]"} ;; *) ext=hs ;; esac
    f=$(echo "$m" | tr . /).$ext
    [ -f "$D/src/$f" ] && f="$D/src/$f" || f="$D/autogen/$f"
    "$GHC" -c "${COMMON[@]}" "$@" "$f" >> "$OUT/log" 2>&1 || { echo "FAIL $OUT $m"; exit 1; }
  done < "$D/order.txt"
fi

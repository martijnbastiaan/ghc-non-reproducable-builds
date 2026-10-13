#!/bin/bash
# Build clash-prelude with ghc directly (no cabal), N times with --make -j1 and
# --make -j4, and once one-shot (ONESHOT=0 to skip; it takes ~7 minutes), then
# compare the normalised --show-iface output of every build with the first -j1
# build.
#
# usage: run.sh [N]
# Needs: the cabal store package db named in flags.txt (ghc-9.12.4), and a
# copy of clash-prelude's src/ and autogen/ next to this script (copied from
# $CLASH_PRELUDE if missing).
set -u
D=$(cd "$(dirname "$0")" && pwd)
N=${1:-3}; G=ghc-9.12.4
CP=${CLASH_PRELUDE:-/home/martijn/code/clash-compiler/clash-prelude}
[ -d "$D/src" ] || cp -r "$CP/src" "$D/src"
O=/home/martijn/code/ghc-non-reproducable-builds/out/clash-prelude-$(date +%Y%m%d-%H%M%S)-$$
mkdir -p "$O"
for i in $(seq 1 "$N"); do
  for j in 1 4; do
    "$D/build.sh" $G make "$O/make-j$j-$i" -j$j +RTS -A128M -RTS
    "$D/sig.sh" $G "$O/make-j$j-$i"
  done
done
if [ "${ONESHOT:-1}" = 1 ]; then
  "$D/build.sh" $G oneshot "$O/oneshot"
  "$D/sig.sh" $G "$O/oneshot"
fi
for d in "$O"/*; do
  [ "$d" = "$O/make-j1-1" ] && continue
  echo "== make-j1-1 vs $(basename "$d")"
  "$D/cmpdirs.sh" $G "$O/make-j1-1" "$d"
done

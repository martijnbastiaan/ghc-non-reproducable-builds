#!/bin/bash
# usage: cmpdirs.sh <ghc> dirA dirB : list modules whose normalised iface differs
D=$(cd "$(dirname "$0")" && pwd)
G=$1; A=$2; B=$3; T=$(mktemp -d /home/martijn/code/ghc-non-reproducable-builds/.tmp/cmpXXXX)
for f in $(cd $A && find . -name '*.hi' | sort); do
  "$D/norm-iface.sh" $G $A/$f > $T/a; "$D/norm-iface.sh" $G $B/$f > $T/b
  cmp -s $T/a $T/b || echo "DIFF $f $(diff $T/a $T/b | grep -c '^[<>]')"
done

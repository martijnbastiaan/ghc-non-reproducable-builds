#!/bin/bash
# usage: mkt.sh <outdir> <ghc flags/targets...> : --make -j1 -fforce-recomp of given targets
D=$(cd "$(dirname "$0")" && pwd)
O=$1; shift; mkdir -p $O
mapfile -t FL < $D/flags.txt
TMPDIR=/home/martijn/code/ghc-non-reproducable-builds/.tmp ghc-9.12.4 --make "${FL[@]}" -i -i$D/src -i$D/autogen -optP-include -optP$D/cabal_macros.h -outputdir $O -odir $O -hidir $O -stubdir $O -this-unit-id clash-prelude-1.11.0-inplace -j1 -fforce-recomp "$@" > $O/log 2>&1 || echo FAIL $O

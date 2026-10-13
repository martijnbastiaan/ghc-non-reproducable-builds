#!/usr/bin/env bash
# Reproducer: the unfolding of B.g (and B's code) depends on which *unrelated*
# modules GHC happened to load interfaces for earlier in the same session.
#
# usage: ./repro.sh                 (uses ghc-9.12.4)
#        GHC=ghc-9.6.7 ./repro.sh
#        FLAGS="-O -fexpose-all-unfoldings -fno-worker-wrapper" ./repro.sh
#        RUNS=20 FILLERS="10 12 14" ./repro.sh   (the -j4 race)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
GHC=${GHC:-ghc-9.12.4}
GHC_PKG=${GHC_PKG:-${GHC/ghc/ghc-pkg}}
FLAGS=${FLAGS:--O}
RUNS=${RUNS:-10}
VER=$($GHC --numeric-version)
OUT=$HERE/out/repro-$VER-$(date +%Y%m%d-%H%M%S)-$$
mkdir -p "$OUT" "$HERE/.tmp"
export TMPDIR=$HERE/.tmp

echo "GHC $VER, flags: $FLAGS"
echo "output: $OUT"

# ghc <outdir> <ghc args...>: compile in a fresh output directory
ghcin() {
  local d=$1; shift
  mkdir -p "$d"
  $GHC -package-env=- $FLAGS -outputdir "$d" "$@" > "$d/log" 2>&1 \
    || { echo "FAILED: $GHC $*"; cat "$d/log"; exit 1; }
}

# unfolding of g in <dir>/B.hi, on one line
unf() {
  $GHC --show-iface "$1/B.hi" \
    | awk '/^  g ::/{p=1} p && /^[0-9a-f]{32}$/{exit} p' \
    | tr -s ' \n' ' ' | sed -E 's/.*:: [A-Za-z.]*Int\) -> //; s/\] *$//'
}

# --show-iface without hashes and absolute paths
norm() { $GHC --show-iface "$1" | grep -v -E '[0-9a-f]{32}' | sed -E "s#$OUT[^ ]*##g"; }

report() { printf '  %-44s g = %s\n' "$1" "$(unf "$2")"; }

#############################################################################
echo
echo "== 1. base + bytestring only (boot/)"
echo "   B does not import A or Z. A and Z only import Data.ByteString.Lazy."
B=$HERE/boot
ghcin "$OUT/b-oneshot" -c "$B/B.hs";                    report "ghc -c B.hs  (one-shot)"              "$OUT/b-oneshot"
ghcin "$OUT/b-make"    --make -j1 -i"$B" B;             report "ghc --make -j1 B"                     "$OUT/b-make"
ghcin "$OUT/b-make-AB" --make -j1 -i"$B" A B;           report "ghc --make -j1 A B  (A built first)"  "$OUT/b-make-AB"
ghcin "$OUT/b-make-BZ" --make -j1 -i"$B" B Z;           report "ghc --make -j1 B Z  (Z built after)"  "$OUT/b-make-BZ"
ghcin "$OUT/b-make-BZ-j4" --make -j4 -i"$B" B Z;        report "ghc --make -j4 B Z  (in parallel)"    "$OUT/b-make-BZ-j4"
echo
echo "  diff of 'ghc --show-iface B.hi', one-shot vs. --make -j1 A B:"
diff <(norm "$OUT/b-oneshot/B.hi") <(norm "$OUT/b-make-AB/B.hi") | sed 's/^/    /'

# A race: Z waits for an empty module S, and B gets some filler bindings, so
# that B's simplifier and Z's import processing run at about the same time. Timing-dependent, so sweep the amount
# of filler; somewhere in the sweep both outcomes should show up.
echo
echo "  ghc --make -j4 B Z, with N filler bindings added to B, $RUNS runs each"
echo "  (o = eqT (f x) g1, I = eqT (h (k x)) g1; timing-dependent):"
for n in ${FILLERS:-0 5 10 15 20 30}; do
  R=$OUT/race-$n-src; mkdir -p "$R"
  # Z waits for an (empty) module S first, so it starts a little later.
  printf 'module S () where\n' > "$R/S.hs"
  sed 's/^import qualified Data.ByteString.Lazy ()/import S ()\n&/' "$B/Z.hs" > "$R/Z.hs"
  { cat "$B/B.hs"
    for i in $(seq 1 "$n"); do
      echo "filler$i :: Int -> Int"
      echo "filler$i x = if x > $i then filler$i (x - 1) * 3 + $i else x"
    done; } > "$R/B.hs"
  res=""
  for i in $(seq 1 "$RUNS"); do
    ghcin "$OUT/race-$n-$i" --make -j4 -i"$R" B Z
    [ "$(unf "$OUT/race-$n-$i")" = "eqT (f x) g1" ] && res="${res}o" || res="${res}I"
  done
  printf '    N=%-3s %s\n' "$n" "$res"
done

#############################################################################
echo
echo "== 2. A rule on an ordinary function, from a small external package (pkg/)"
echo "   Package p: P.Fun defines fun, P.Rule defines RULE \"fun/bar\" fun (bar x) = x."
P=$OUT/pkg-p
ghcin "$P/build" --make -this-unit-id p-0 -i"$HERE/pkg/p" P.Fun P.Rule
ar rcs "$P/build/libHSp-0.a" "$P"/build/P/*.o
$GHC_PKG init "$P/db" > /dev/null
cat > "$P/p.conf" <<EOF
name: p
version: 0
id: p-0
key: p-0
exposed: True
exposed-modules: P.Fun P.Rule
import-dirs: $P/build
library-dirs: $P/build
hs-libraries: HSp-0
depends: $($GHC_PKG field base id --simple-output)
EOF
$GHC_PKG --package-db "$P/db" register --force "$P/p.conf" > /dev/null 2>&1 \
  || { echo "ghc-pkg register failed"; exit 1; }
PK=(-package-db "$P/db" -package p)
ghcin "$OUT/p-oneshot" "${PK[@]}" -c "$HERE/pkg/app/B.hs";        report "ghc -c B.hs  (one-shot)"             "$OUT/p-oneshot"
ghcin "$OUT/p-make"    "${PK[@]}" --make -j1 -i"$HERE/pkg/app" B;   report "ghc --make -j1 B"                    "$OUT/p-make"
ghcin "$OUT/p-make-AB" "${PK[@]}" --make -j1 -i"$HERE/pkg/app" A B; report "ghc --make -j1 A B  (A built first)" "$OUT/p-make-AB"
echo
echo "  diff of 'ghc --show-iface B.hi', one-shot vs. --make -j1 A B:"
diff <(norm "$OUT/p-oneshot/B.hi") <(norm "$OUT/p-make-AB/B.hi") | sed 's/^/    /'

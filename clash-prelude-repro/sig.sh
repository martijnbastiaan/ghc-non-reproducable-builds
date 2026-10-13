#!/bin/bash
# usage: sig.sh <ghc> <outdir> : short fingerprint of the unstable unfoldings
D=$(cd "$(dirname "$0")" && pwd)
u=$("$D/norm-iface.sh" $1 $2/Clash/Sized/Internal/Unsigned.hi | grep -c 'fBitPackUnsigned2 @n \$dKnownNat v')
s=$("$D/norm-iface.sh" $1 $2/Clash/Sized/Internal/Signed.hi | grep -c 'fBitPackSigned2 @n \$dKnownNat v')
e=$("$D/norm-iface.sh" $1 $2/Clash/Explicit/Signal.hi | grep -c 'tbClockGen')
echo "$(basename $2): U=$u S=$s ES.tbClockGen=$e"

#!/bin/bash
# usage: norm-iface.sh <ghc> <hi file> : --show-iface without hashes and absolute paths
"$1" --show-iface "$2" | sed -E 's#/home/[^ ]*##g' | grep -v -E '[0-9a-f]{32}'

#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# Copy the driver into a kernel tree, dropping the blocks this repository
# carries for distribution kernels but the upstream tree does not need.
#
# Each such block is fenced with "NOT-UPSTREAM begin/end". Removing them by
# hand is how the two trees quietly drift apart, so it is done here and the
# script fails if a fence is missing or unbalanced.
#
#   sh scripts/to-upstream.sh ~/media_stage
set -e

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tree=${1:?usage: to-upstream.sh <kernel tree>}
src="$repo/src/ov32c4.c"
dst="$tree/drivers/media/i2c/ov32c4.c"

[ -d "$tree/drivers/media/i2c" ] || { echo "$tree is not a kernel tree" >&2; exit 1; }

begin=$(grep -c 'NOT-UPSTREAM begin' "$src" || true)
end=$(grep -c 'NOT-UPSTREAM end' "$src" || true)
[ "$begin" -gt 0 ] || { echo "no NOT-UPSTREAM block found - has the fence been lost?" >&2; exit 1; }
[ "$begin" = "$end" ] || { echo "unbalanced NOT-UPSTREAM fences: $begin begin, $end end" >&2; exit 1; }

sed '/NOT-UPSTREAM begin/,/NOT-UPSTREAM end/d' "$src" > "$dst"

echo "wrote $dst ($begin block(s) dropped)"
if grep -q 'NOT-UPSTREAM' "$dst"; then
	echo "a fence survived the copy" >&2
	exit 1
fi

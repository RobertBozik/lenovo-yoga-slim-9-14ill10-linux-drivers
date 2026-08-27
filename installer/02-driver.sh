#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# ov32c4 sensor driver and patched ipu-bridge, built by DKMS
#
# Both modules land in /lib/modules/<kernel>/updates/dkms/, which depmod
# prefers over the distribution ones, and DKMS rebuilds them for every new
# kernel. The sensor driver is ours (upstream submission in upstream/);
# ipu-bridge is the kernel's own file with one line added, see
# vendor/ipu-bridge/README.md.
#
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

NAME=ov32c4-camera
VER=1.0
SRC="/usr/src/$NAME-$VER"
# The kernel version vendor/ipu-bridge/ipu-bridge.c was taken from.
IPU_BRIDGE_FROM="7.0.0-30-generic"

case "$ACTION" in
install)
	need_root
	command -v dkms >/dev/null || die "dkms missing (step: packages)"

	if [ "$KVER" != "$IPU_BRIDGE_FROM" ]; then
		warn "vendor/ipu-bridge/ipu-bridge.c is a copy from $IPU_BRIDGE_FROM,"
		warn "this kernel is $KVER - if the build fails, refresh that copy"
		warn "(see vendor/ipu-bridge/README.md)."
	fi

	mkdir -p "$SRC"
	install -m 644 "$REPO/src/ov32c4.c" "$SRC/ov32c4.c"
	install -m 644 "$REPO/vendor/ipu-bridge/ipu-bridge.c" "$SRC/ipu-bridge.c"
	install -m 644 "$REPO/dkms/dkms.conf" "$REPO/dkms/Kbuild" "$SRC/"

	# Older manual copies of the same modules would shadow the DKMS ones.
	for m in ov32c4.ko ipu-bridge.ko; do
		f="/lib/modules/$KVER/updates/$m"
		[ -e "$f" ] && { info "removing stale manual copy $f"; rm -f "$f"; }
	done

	if dkms status "$NAME/$VER" 2>/dev/null | grep -q .; then
		dkms remove "$NAME/$VER" --all >/dev/null
	fi
	dkms add "$NAME/$VER" >/dev/null
	dkms build "$NAME/$VER" -k "$KVER"
	dkms install "$NAME/$VER" -k "$KVER" --force
	depmod -a "$KVER"

	for m in ov32c4 ipu_bridge; do
		p="$(modinfo -n "$m" -k "$KVER" 2>/dev/null || true)"
		case "$p" in
		*/updates/dkms/*) ok "$m -> $p" ;;
		*) die "$m does not resolve to the DKMS module ($p)" ;;
		esac
	done
	info "the modules are not swapped while running - reboot to use them"
	;;

uninstall)
	need_root
	if dkms status "$NAME/$VER" 2>/dev/null | grep -q .; then
		dkms remove "$NAME/$VER" --all
	fi
	rm -rf "$SRC"
	depmod -a "$KVER" || true
	ok "DKMS package removed (reboot to fall back to the stock modules)"
	;;

check)
	if dkms status "$NAME/$VER" 2>/dev/null | grep -q "$KVER"; then
		report dkms ok "$(dkms status "$NAME/$VER" | head -1)"
	else
		report dkms missing "not built for $KVER"
		exit 1
	fi
	# The i2c client is enumerated from ACPI, so it is called
	# i2c-OVTI32C4:00 rather than <bus>-<addr>; count the symlinks to
	# devices instead of guessing the name.
	names=""
	if [ -d /sys/bus/i2c/drivers/ov32c4 ]; then
		for d in /sys/bus/i2c/drivers/ov32c4/*; do
			case "${d##*/}" in bind | unbind | uevent | module | '*') continue ;; esac
			[ -L "$d" ] && names="$names ${d##*/}"
		done
	fi
	if [ -n "$names" ]; then
		report "sensor driver bound" ok "${names# }"
	else
		report "sensor driver bound" missing "module loaded? reboot done?"
	fi
	;;
esac

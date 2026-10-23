#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Xe kernel parameters that stop the display from blanking
#
# With panel self-refresh enabled, this panel goes black for a moment
# during video calls and under some compositor load. Disabling PSR and
# panel replay for the Xe driver stops it. The cost is a little more
# power when the screen is idle.
#
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

GRUB=/etc/default/grub
# grub-mkconfig on Debian and Ubuntu sources /etc/default/grub.d/*.cfg
# after /etc/default/grub, so the parameters live in a file of our own
# and the user's file is not rewritten. Earlier versions of this step
# appended them to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub, and
# a value with nothing in it came out mangled.
DROPIN=/etc/default/grub.d/ov32c4-xe.cfg
PARAMS="xe.enable_psr=0 xe.enable_panel_replay=0"

# Take the parameters out of /etc/default/grub, where earlier versions of
# this step put them. Only that one line is edited, token by token, so
# its quoting and the rest of the value stay as they are.
strip_legacy() {
	local p changed=0
	[ -f "$GRUB" ] || return 0
	for p in $PARAMS; do
		grep -qE "^GRUB_CMDLINE_LINUX_DEFAULT=.*${p//./\\.}" "$GRUB" || continue
		[ -e "$GRUB.ov32c4.bak" ] || cp -a "$GRUB" "$GRUB.ov32c4.bak"
		sed -i -E "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/ ?${p//./\\.}//g" "$GRUB"
		changed=1
	done
	[ $changed = 0 ] || info "moved the parameters out of $GRUB (backup: $GRUB.ov32c4.bak)"
}

case "$ACTION" in
install)
	need_root
	[ -f "$GRUB" ] || die "$GRUB not found (not a GRUB system?)"
	mkconfig="$(command -v grub-mkconfig || true)"
	if [ -z "$mkconfig" ] || ! grep -q 'default/grub.d' "$mkconfig"; then
		die "this grub-mkconfig does not read /etc/default/grub.d - add \"$PARAMS\" to the kernel command line by hand"
	fi

	tmp="$(mktemp)"
	cat >"$tmp" <<EOF
# Written by install.sh --step graphics (lenovo-yoga-slim-9-14ill10-linux-drivers).
# Panel self-refresh and panel replay off for Xe: the panel stops blanking.
GRUB_CMDLINE_LINUX_DEFAULT="\$GRUB_CMDLINE_LINUX_DEFAULT $PARAMS"
EOF
	changed=0
	cmp -s "$tmp" "$DROPIN" || changed=1
	install_file "$tmp" "$DROPIN"
	rm -f "$tmp"
	legacy="$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB" || true)"
	strip_legacy
	[ "$legacy" = "$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB" || true)" ] || changed=1

	if [ $changed = 0 ]; then
		ok "parameters already in $DROPIN"
	else
		update-grub >/dev/null 2>&1 || die "update-grub failed - check $GRUB and $DROPIN"
		ok "added $PARAMS in $DROPIN"
		info "takes effect after a reboot"
	fi
	;;

uninstall)
	need_root
	remove_file "$DROPIN"
	strip_legacy
	update-grub >/dev/null 2>&1 || warn "update-grub failed"
	ok "parameters removed"
	;;

check)
	ingrub=1; running=1
	for p in $PARAMS; do
		grep -qs "$p" "$DROPIN" ||
			grep -qE "^GRUB_CMDLINE_LINUX_DEFAULT=.*${p//./\\.}" "$GRUB" || ingrub=0
		grep -q "$p" /proc/cmdline || running=0
	done
	[ $ingrub = 1 ] && report "grub parameters" ok || { report "grub parameters" missing; exit 1; }
	[ $running = 1 ] && report "active in this boot" ok || report "active in this boot" "TODO" "reboot pending"
	;;
esac

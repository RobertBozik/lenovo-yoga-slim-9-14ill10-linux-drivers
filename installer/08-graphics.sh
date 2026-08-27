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
PARAMS="xe.enable_psr=0 xe.enable_panel_replay=0"

grub_line() { grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB" | head -1; }

case "$ACTION" in
install)
	need_root
	[ -f "$GRUB" ] || die "$GRUB not found (not a GRUB system?)"
	cur="$(grub_line)"
	[ -n "$cur" ] || die "no GRUB_CMDLINE_LINUX_DEFAULT line in $GRUB"

	missing=""
	for p in $PARAMS; do
		case "$cur" in *"$p"*) ;; *) missing="$missing $p" ;; esac
	done
	if [ -z "$missing" ]; then
		ok "parameters already in $GRUB"
	else
		cp -a "$GRUB" "$GRUB.ov32c4.bak"
		value="$(printf '%s' "$cur" | sed -E 's/^GRUB_CMDLINE_LINUX_DEFAULT="?(.*[^"])"?$/\1/')"
		new="GRUB_CMDLINE_LINUX_DEFAULT=\"$value$missing\""
		sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|$new|" "$GRUB"
		ok "added:$missing"
		info "backup: $GRUB.ov32c4.bak"
		update-grub >/dev/null 2>&1 || die "update-grub failed - check $GRUB"
		info "takes effect after a reboot"
	fi
	;;

uninstall)
	need_root
	cur="$(grub_line)"
	value="$(printf '%s' "$cur" | sed -E 's/^GRUB_CMDLINE_LINUX_DEFAULT="?(.*[^"])"?$/\1/')"
	for p in $PARAMS; do value="${value//$p/}"; done
	value="$(printf '%s' "$value" | tr -s ' ' | sed 's/^ *//; s/ *$//')"
	sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$value\"|" "$GRUB"
	update-grub >/dev/null 2>&1 || warn "update-grub failed"
	ok "parameters removed from $GRUB"
	;;

check)
	ingrub=1; running=1
	for p in $PARAMS; do
		grep -q "$p" "$GRUB" || ingrub=0
		grep -q "$p" /proc/cmdline || running=0
	done
	[ $ingrub = 1 ] && report "grub parameters" ok || { report "grub parameters" missing; exit 1; }
	[ $running = 1 ] && report "active in this boot" ok || report "active in this boot" "TODO" "reboot pending"
	;;
esac

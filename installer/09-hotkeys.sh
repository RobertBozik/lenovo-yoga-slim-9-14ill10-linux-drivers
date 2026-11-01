#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# on-screen messages for the camera switch and the performance key
#
# Windows shows a popup when the camera switch is flipped or the
# performance key cycles the power mode; under Linux both work but
# nothing says so. The camera switch is the one that matters: it cuts
# the picture in hardware with no error anywhere, so the camera just
# looks broken. The embedded controller reports the switch on "Ideapad
# extra buttons" as scan codes 0x10c / 0x10d, which ideapad-laptop does
# not map to any key, so a udev rule lets the logged-in user read that
# device. The performance key is handled by the firmware, which changes
# the platform profile and sends no key; the kernel notifies readers of
# /sys/firmware/acpi/platform_profile. A small session service turns
# both into a Plasma OSD (or a notification on other desktops).
#
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SRC="$REPO/tools/hotkeys"
BIN=/usr/local/bin/yoga-hotkeys
UNIT=/etc/systemd/user/yoga-hotkeys.service
UDEV=/etc/udev/rules.d/71-yoga-hotkeys.rules
LINK=/dev/input/yoga-hotkeys
PROFILE=/sys/firmware/acpi/platform_profile

# The first version of this step was called camswitch and only handled
# the camera switch.
OLD_UNIT=/etc/systemd/user/camera-switch-osd.service
OLD_BIN=/usr/local/bin/camera-switch-osd
OLD_UDEV=/etc/udev/rules.d/71-yoga-camera-switch.rules

# Re-run udev on the hotkeys' event node, so that the rule (or its
# removal) takes effect without a reboot.
retrigger() {
	local e
	udevadm control --reload
	for e in /sys/class/input/event*; do
		[ "$(cat "$e/device/name" 2>/dev/null)" = "Ideapad extra buttons" ] || continue
		udevadm trigger --settle --action=change --sysname-match="${e##*/}"
	done
}

remove_camswitch() {
	[ -e "$OLD_UNIT" ] || [ -e "$OLD_BIN" ] || [ -e "$OLD_UDEV" ] || return 0
	info "replacing the camswitch step"
	user_systemctl disable --now camera-switch-osd.service
	remove_file "$OLD_UNIT"
	remove_file "$OLD_BIN"
	remove_file "$OLD_UDEV"
}

case "$ACTION" in
install)
	need_root
	remove_camswitch
	install_file "$SRC/71-yoga-hotkeys.rules" "$UDEV"
	install_file "$SRC/yoga-hotkeys" "$BIN" 755
	install_file "$SRC/yoga-hotkeys.service" "$UNIT"
	retrigger
	[ -e "$LINK" ] || warn "$LINK did not appear - is this an 83CX with ideapad-laptop loaded?"
	[ -e "$PROFILE" ] || warn "$PROFILE missing - no messages for the performance key"

	user_systemctl daemon-reload
	user_systemctl enable yoga-hotkeys.service
	user_systemctl restart yoga-hotkeys.service
	ok "hotkey messages installed"
	;;

uninstall)
	need_root
	user_systemctl disable --now yoga-hotkeys.service
	remove_file "$UNIT"
	remove_file "$BIN"
	remove_file "$UDEV"
	remove_camswitch
	retrigger
	user_systemctl daemon-reload
	;;

check)
	[ -f "$UDEV" ] && [ -e "$LINK" ] && report "camera switch device" ok "$LINK -> $(readlink "$LINK")" ||
		{ report "camera switch device" missing "$LINK"; exit 1; }
	[ -e "$PROFILE" ] && report "platform profile" ok "$(cat "$PROFILE")" ||
		report "platform profile" missing "$PROFILE"
	if as_user systemctl --user is-active yoga-hotkeys.service >/dev/null 2>&1; then
		report "hotkeys service" ok
	else
		report "hotkeys service" missing "needs a graphical session"
	fi
	;;
esac

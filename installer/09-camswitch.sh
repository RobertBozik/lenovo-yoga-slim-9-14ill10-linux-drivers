#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# on-screen message when the hardware camera switch is flipped
#
# The switch cuts the picture in hardware: the sensor keeps streaming,
# every pixel is zero, and nothing reports an error, so the camera just
# looks broken. Windows shows a popup; this does the same. The embedded
# controller reports the switch on "Ideapad extra buttons" as scan codes
# 0x10c / 0x10d, which ideapad-laptop does not map to any key. A udev
# rule lets the logged-in user read that device, and a small session
# service turns the scan codes into a Plasma OSD (or a notification on
# other desktops).
#
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SRC="$REPO/tools/camera-switch"
BIN=/usr/local/bin/camera-switch-osd
UNIT=/etc/systemd/user/camera-switch-osd.service
UDEV=/etc/udev/rules.d/71-yoga-camera-switch.rules
LINK=/dev/input/yoga-camera-switch

# Re-run udev on the switch's event node, so that the rule (or its
# removal) takes effect without a reboot.
retrigger() {
	local e
	udevadm control --reload
	for e in /sys/class/input/event*; do
		[ "$(cat "$e/device/name" 2>/dev/null)" = "Ideapad extra buttons" ] || continue
		udevadm trigger --settle --action=change --sysname-match="${e##*/}"
	done
}

case "$ACTION" in
install)
	need_root
	install_file "$SRC/71-yoga-camera-switch.rules" "$UDEV"
	install_file "$SRC/camera-switch-osd" "$BIN" 755
	install_file "$SRC/camera-switch-osd.service" "$UNIT"
	retrigger
	[ -e "$LINK" ] || warn "$LINK did not appear - is this an 83CX with ideapad-laptop loaded?"

	user_systemctl daemon-reload
	user_systemctl enable camera-switch-osd.service
	user_systemctl restart camera-switch-osd.service
	ok "camera switch messages installed"
	;;

uninstall)
	need_root
	user_systemctl disable --now camera-switch-osd.service
	remove_file "$UNIT"
	remove_file "$BIN"
	remove_file "$UDEV"
	retrigger
	user_systemctl daemon-reload
	;;

check)
	[ -f "$UDEV" ] && [ -e "$LINK" ] && report "camera switch device" ok "$LINK -> $(readlink "$LINK")" ||
		{ report "camera switch device" missing "$LINK"; exit 1; }
	if as_user systemctl --user is-active camera-switch-osd.service >/dev/null 2>&1; then
		report "camera switch service" ok
	else
		report "camera switch service" missing "needs a graphical session"
	fi
	;;
esac

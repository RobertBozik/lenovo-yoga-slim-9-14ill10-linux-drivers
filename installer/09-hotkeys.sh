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
# The eye key (KEY_PROG3, "Launch (3)" in Plasma) is eye care under
# Windows. Plasma has no default shortcut for it, so in a Plasma session
# it is made to toggle Night Color - only if Night Color has no shortcut
# yet and nothing else uses the key, and uninstall takes it out again
# only if it is still the one set here. The two star keys are left for
# the user to assign; until they are, a press opens the shortcut settings.
#
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SRC="$REPO/tools/hotkeys"
BIN=/usr/local/bin/yoga-hotkeys
UNIT=/etc/systemd/user/yoga-hotkeys.service
UDEV=/etc/udev/rules.d/71-yoga-hotkeys.rules
LINK=/dev/input/yoga-hotkeys
PROFILE=/sys/firmware/acpi/platform_profile

# Night Color shortcut, set through KWin's global shortcut service (the
# config file cannot be edited while the session runs; KWin owns it).
NC_ID=(kwin "Toggle Night Color" KWin "Toggle Night Color")
NC_KEY=16777381 # Qt::Key_Launch3, which is what Plasma calls the eye key
NC_OURS="a(ai) 1 4 $NC_KEY 0 0 0"
NC_MARK=/var/lib/ov32c4-installer/night-color-shortcut

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

kglobalaccel() {
	as_user busctl --user call org.kde.kglobalaccel /kglobalaccel \
		org.kde.KGlobalAccel "$@" 2>/dev/null
}

night_color_keys() { kglobalaccel shortcutKeys as 4 "${NC_ID[@]}"; }

set_night_color_shortcut() {
	local cur
	if ! cur="$(night_color_keys)"; then
		info "no Plasma session - the eye key is left alone"
		return 0
	fi
	case "$cur" in
	"$NC_OURS") ok "the eye key already toggles Night Color"; return 0 ;;
	"a(ai) 0") ;;
	*) info "Night Color already has a shortcut of its own - left alone"; return 0 ;;
	esac
	if [ "$(kglobalaccel getGlobalShortcutsByKey i "$NC_KEY")" != "a(ssssssaiai) 0" ]; then
		info "the eye key is already used for something else - left alone"
		return 0
	fi
	if ! kglobalaccel setForeignShortcutKeys "asa(ai)" 4 "${NC_ID[@]}" 1 4 "$NC_KEY" 0 0 0 ||
		[ "$(night_color_keys)" != "$NC_OURS" ]; then
		warn "could not set the Night Color shortcut"
		return 0
	fi
	mkdir -p "$(dirname "$NC_MARK")"
	touch "$NC_MARK"
	ok "the eye key now toggles Night Color"
}

unset_night_color_shortcut() {
	[ -e "$NC_MARK" ] || return 0
	if [ "$(night_color_keys)" = "$NC_OURS" ]; then
		kglobalaccel setForeignShortcutKeys "asa(ai)" 4 "${NC_ID[@]}" 0 &&
			info "removed the Night Color shortcut from the eye key"
	fi
	rm -f "$NC_MARK"
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
	set_night_color_shortcut
	;;

uninstall)
	need_root
	user_systemctl disable --now yoga-hotkeys.service
	unset_night_color_shortcut
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
	case "$(night_color_keys)" in
	"$NC_OURS") report "eye key: Night Color" ok ;;
	"") report "eye key: Night Color" "n/a" "no Plasma session" ;;
	*) report "eye key: Night Color" "-" "Night Color has another or no shortcut" ;;
	esac
	;;
esac

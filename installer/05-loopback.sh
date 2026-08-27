#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# /dev/video42, so that ordinary v4l2 applications see the camera
#
# Programs that speak plain v4l2 (Zoom, Viber, browsers without flags)
# cannot see a libcamera-only camera, and two PipeWire clients of
# libcamera crash today. So a v4l2loopback node called "Lenovo OV32C4"
# is created, a small watcher keeps it open and feeds it frames from
# libcamera whenever something reads from it, and WirePlumber hides the
# loopback from PipeWire applications so the camera is not offered twice.
#
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SRC="$REPO/tools/loopback"
WATCH_BIN=/usr/local/bin/ov32c4-camera-watch
UNIT=/etc/systemd/user/ov32c4-camera-watch.service
MODPROBE=/etc/modprobe.d/ov32c4-loopback.conf
MODLOAD=/etc/modules-load.d/ov32c4-loopback.conf
UDEV=/etc/udev/rules.d/99-ov32c4-loopback.rules
WPRULE=/etc/wireplumber/wireplumber.conf.d/50-ov32c4-loopback-hide.conf

case "$ACTION" in
install)
	need_root
	command -v v4l2loopback-ctl >/dev/null || die "v4l2loopback-utils missing (step: packages)"
	gst-inspect-1.0 libcamerasrc >/dev/null 2>&1 ||
		warn "gst libcamerasrc not found yet - run the libcamera step first"

	install_file "$SRC/ov32c4-loopback-modprobe.conf" "$MODPROBE"
	install_file "$SRC/ov32c4-loopback-modules-load.conf" "$MODLOAD"
	install_file "$SRC/99-ov32c4-loopback.rules" "$UDEV"
	install_file "$SRC/50-ov32c4-loopback-hide.conf" "$WPRULE"
	install_file "$SRC/ov32c4-camera-watch" "$WATCH_BIN" 755
	install_file "$SRC/ov32c4-camera-watch.service" "$UNIT"

	# /dev/video* and /dev/udmabuf are group-owned; without membership the
	# session races logind's ACLs and libcamera gives up after EACCES.
	usermod -aG video,kvm "$TARGET_USER"
	info "$TARGET_USER added to groups video and kvm (takes effect on next login)"

	udevadm control --reload
	modprobe -r v4l2loopback 2>/dev/null || true
	modprobe v4l2loopback
	udevadm settle
	sleep 1
	if ! v4l2-ctl -d /dev/video42 --info 2>/dev/null | grep -q 'Video Capture'; then
		v4l2loopback-ctl set-caps /dev/video42 "YUYV:1280x720@15" || true
	fi

	user_systemctl daemon-reload
	user_systemctl enable --now ov32c4-camera-watch.service
	user_systemctl restart wireplumber.service
	ok "loopback node /dev/video42 ready"
	;;

uninstall)
	need_root
	user_systemctl disable --now ov32c4-camera-watch.service
	remove_file "$UNIT"
	remove_file "$WATCH_BIN"
	remove_file "$MODPROBE"
	remove_file "$MODLOAD"
	remove_file "$UDEV"
	remove_file "$WPRULE"
	udevadm control --reload || true
	modprobe -r v4l2loopback 2>/dev/null || true
	user_systemctl daemon-reload
	user_systemctl restart wireplumber.service
	info "group membership (video, kvm) left in place"
	;;

check)
	[ -e /dev/video42 ] && report "/dev/video42" ok "$(v4l2-ctl -d /dev/video42 --info 2>/dev/null | sed -n 's/\tCard type *: //p')" ||
		{ report "/dev/video42" missing; exit 1; }
	if as_user systemctl --user is-active ov32c4-camera-watch.service >/dev/null 2>&1; then
		report "feeder service" ok
	else
		report "feeder service" missing "systemctl --user status ov32c4-camera-watch"
	fi
	[ -f "$WPRULE" ] && report "wireplumber rule" ok || report "wireplumber rule" missing
	;;
esac

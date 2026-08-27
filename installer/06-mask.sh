#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# black dot on the panel above the lens while the camera streams
#
# The camera sits under the OLED panel. When the pixels above the lens
# are lit, their own light goes straight into it: the picture gets a
# veil, loses contrast, and the panel's pixel grid becomes visible in
# it. Windows blanks that spot with a separate driver; here a small
# always-on-top window does the same. Black on OLED means the pixels
# are off, so the result for the camera is the same.
#
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BIN=/usr/local/bin/udc-mask.py
UNIT=/etc/systemd/user/udc-mask.service

case "$ACTION" in
install)
	need_root
	python3 -c 'import PyQt6' 2>/dev/null || die "python3-pyqt6 missing (step: packages)"

	# An older hand-made per-user unit would shadow the system one, and
	# its enable symlink would be left dangling. Take it out of service
	# first, so that systemd removes the symlink while the file is still
	# there, and only then delete it.
	old="$TARGET_HOME/.config/systemd/user/udc-mask.service"
	if [ -e "$old" ]; then
		info "replacing the per-user unit $old"
		user_systemctl disable --now udc-mask.service
		rm -f "$old"
		user_systemctl daemon-reload
	fi

	install_file "$REPO/scripts/udc-mask.py" "$BIN" 755

	cat >/tmp/udc-mask.service <<EOF
[Unit]
Description=Black mask over the under-display camera lens
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $BIN
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF
	install_file /tmp/udc-mask.service "$UNIT"
	rm -f /tmp/udc-mask.service

	user_systemctl daemon-reload
	user_systemctl enable --now udc-mask.service

	cfg="$TARGET_HOME/.config/udc-mask.json"
	if [ -f "$cfg" ] && grep -q '"calibrated": *true' "$cfg"; then
		ok "mask service running, position already calibrated"
	else
		ok "mask service installed"
		info "calibrate once (white screen, arrows move the dot, Enter saves):"
		info "  python3 $BIN --calibrate"
	fi
	;;

uninstall)
	need_root
	user_systemctl disable --now udc-mask.service
	remove_file "$UNIT"
	remove_file "$BIN"
	user_systemctl daemon-reload
	info "the calibration in ~/.config/udc-mask.json is left alone"
	;;

check)
	[ -x "$BIN" ] && report "mask program" ok || { report "mask program" missing; exit 1; }
	if as_user systemctl --user is-active udc-mask.service >/dev/null 2>&1; then
		report "mask service" ok
	else
		report "mask service" missing "needs a graphical session"
	fi
	cfg="$TARGET_HOME/.config/udc-mask.json"
	if [ -f "$cfg" ] && grep -q '"calibrated": *true' "$cfg"; then
		report "mask calibration" ok "$(tr -d '\n ' <"$cfg")"
	else
		report "mask calibration" "TODO" "python3 $BIN --calibrate"
	fi
	;;
esac

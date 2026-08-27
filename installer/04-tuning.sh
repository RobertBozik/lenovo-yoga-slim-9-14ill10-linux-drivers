#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# software ISP tuning file for the OV32C4
#
# Everything the software ISP needs to know about this camera - black
# level, lens shading, the white balance curve, the colour matrices, the
# noise model, exposure and metering - lives in one file. It is in this
# repository; nothing is fetched or extracted at install time.
#
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DEST_DIR="/usr/local/share/libcamera/ipa/softisp"
DEST="$DEST_DIR/ov32c4.yaml"
SRC="$REPO/tuning/ov32c4.yaml"

case "$ACTION" in
install)
	need_root
	[ -f "$SRC" ] || die "$SRC is missing"

	# A tuning file that does not parse gives a camera that starts and
	# then produces nothing useful, which is a horrible thing to debug.
	if command -v python3 >/dev/null && python3 -c 'import yaml' 2>/dev/null; then
		python3 - "$SRC" <<-'PY' || die "$SRC is not a valid tuning file"
			import sys, yaml
			d = yaml.safe_load(open(sys.argv[1]))
			names = [list(a)[0] for a in d["algorithms"]]
			want = ["BlackLevel", "Lsc", "Awb", "Ccm", "Denoise", "Adjust", "Agc"]
			assert names == want, "algorithms are %s, expected %s" % (names, want)
		PY
	fi

	install -d "$DEST_DIR"
	install_file "$SRC" "$DEST" 644
	ok "installed $DEST"
	info "restart the camera feeder to pick it up:"
	info "  systemctl --user restart ov32c4-camera-watch"
	;;

uninstall)
	need_root
	remove_file "$DEST"
	;;

check)
	if [ ! -f "$DEST" ]; then
		report tuning missing
		exit 1
	fi
	if cmp -s "$SRC" "$DEST"; then
		report tuning ok "$DEST"
	else
		report tuning "OLD" "differs from $SRC - re-run --step tuning"
	fi
	;;
esac

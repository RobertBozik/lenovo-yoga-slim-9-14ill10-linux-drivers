#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Lenovo Yoga Slim 9 14ILL10 - camera, sound and graphics fixes for Linux.
#
#   sudo bash install.sh                 # everything
#   sudo bash install.sh --list          # what the steps are
#   sudo bash install.sh --step driver --step loopback
#   sudo bash install.sh --skip libcamera
#   sudo bash install.sh --check         # report what is installed
#
# The steps are independent scripts under installer/ and each one knows
# how to install, uninstall and check itself, so a step can be re-run at
# any time. See uninstall.sh for the reverse.
#
# What this machine needs:
#   packages   build dependencies
#   driver     out-of-tree ov32c4 sensor driver + patched ipu-bridge, via DKMS
#   libcamera  libcamera built from source with the OV32C4 patches, in /usr/local
#   tuning     the software ISP tuning file for this sensor
#   loopback   /dev/video42 so ordinary v4l2 applications see the camera
#   mask       black dot on the panel above the lens while the camera streams
#   audio      speaker routing fixup for the ALC287 codec
#   graphics   Xe kernel parameters that stop the display from blanking
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEPS_DIR="$REPO/installer"

BOLD=$'\033[1m'; OFF=$'\033[0m'
[ -t 1 ] || { BOLD=""; OFF=""; }

ALL_STEPS=(packages driver libcamera tuning loopback mask audio graphics)

usage() {
	cat <<EOF
usage: sudo bash install.sh [--step NAME]... [--skip NAME]... [--check] [--list]

steps: ${ALL_STEPS[*]}
EOF
}

list_steps() {
	local n f
	for n in "${ALL_STEPS[@]}"; do
		f="$(step_file "$n")"
		# The description is the first real comment line of the step
		# script - not a fixed line number, so that an SPDX tag or an
		# extra comment above it does not silently blank the listing.
		printf '  %-10s %s\n' "$n" \
			"$(sed -n '1,8{/^#!/d; /SPDX-License-Identifier/d; /^#$/d; s/^# //p}' "$f" | head -1)"
	done
}

step_file() {
	local n="$1" f
	f="$(find "$STEPS_DIR" -maxdepth 1 -name "[0-9][0-9]-$n.sh" -print -quit)"
	[ -n "$f" ] || { echo "no such step: $n" >&2; exit 1; }
	printf '%s\n' "$f"
}

WANT=(); SKIP=(); ACTION=install
while [ $# -gt 0 ]; do
	case "$1" in
	--step) WANT+=("$2"); shift 2 ;;
	--skip) SKIP+=("$2"); shift 2 ;;
	--check) ACTION=check; shift ;;
	--uninstall) ACTION=uninstall; shift ;;
	--list) list_steps; exit 0 ;;
	-h | --help) usage; exit 0 ;;
	*) usage >&2; exit 1 ;;
	esac
done

[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }

# The user whose session gets the user services and the group membership.
TARGET_USER="${SUDO_USER:-}"
[ -n "$TARGET_USER" ] && [ "$TARGET_USER" != root ] ||
	{ echo "run with sudo from your normal account, not as root" >&2; exit 1; }
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
KVER="$(uname -r)"

export REPO STEPS_DIR TARGET_USER TARGET_HOME KVER

# Sanity: this is written for one laptop. Warn, but let people try.
PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
VERSION="$(cat /sys/class/dmi/id/product_version 2>/dev/null || true)"
case "$VERSION$PRODUCT" in
*"Yoga Slim 9 14ILL10"* | *83CX*) ;;
*)
	echo "${BOLD}This is meant for a Lenovo Yoga Slim 9 14ILL10 (83CX).${OFF}"
	echo "This machine reports: ${PRODUCT:-?} / ${VERSION:-?}"
	printf 'Continue anyway? [y/N] '
	read -r a </dev/tty
	case "$a" in [yY]*) ;; *) exit 1 ;; esac
	;;
esac

run=()
if [ ${#WANT[@]} -gt 0 ]; then
	run=("${WANT[@]}")
else
	for s in "${ALL_STEPS[@]}"; do
		skip=0
		for k in ${SKIP[@]+"${SKIP[@]}"}; do [ "$k" = "$s" ] && skip=1; done
		[ $skip = 0 ] && run+=("$s")
	done
fi

# Uninstall runs the steps in reverse order.
if [ "$ACTION" = uninstall ]; then
	rev=(); for ((i = ${#run[@]} - 1; i >= 0; i--)); do rev+=("${run[$i]}"); done
	run=("${rev[@]}")
fi

failed=()
for s in "${run[@]}"; do
	f="$(step_file "$s")"
	printf '\n%s== %s (%s)%s\n' "$BOLD" "$s" "$ACTION" "$OFF"
	if ! bash "$f" "$ACTION"; then
		failed+=("$s")
		[ "$ACTION" = check ] || echo "  step '$s' failed" >&2
	fi
done

printf '\n'
if [ ${#failed[@]} -gt 0 ]; then
	printf '%sfinished with problems in: %s%s\n' "$BOLD" "${failed[*]}" "$OFF"
	exit 1
fi

if [ "$ACTION" = install ]; then
	# Only the steps that touch kernel modules or the kernel command line
	# need a reboot; saying so after every single step trains people to
	# ignore it.
	needs_reboot=0
	for s in "${run[@]}"; do
		case "$s" in driver | graphics | audio) needs_reboot=1 ;; esac
	done
	if [ "$needs_reboot" = 1 ]; then
		cat <<EOF
${BOLD}Done.${OFF} Reboot now: the sensor driver and ipu-bridge are not
swapped while running, and the kernel parameters need a new boot.

After the reboot:
  sudo bash install.sh --check      # everything should say ok
EOF
	else
		printf '%sDone.%s  sudo bash install.sh --check\n' "$BOLD" "$OFF"
	fi
	if [ ! -f "$TARGET_HOME/.config/udc-mask.json" ]; then
		echo "  python3 /usr/local/bin/udc-mask.py --calibrate    # once, to place the dot"
	fi
fi

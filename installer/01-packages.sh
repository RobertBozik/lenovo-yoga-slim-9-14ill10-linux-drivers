#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# build dependencies
#
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BUILD_PKGS=(
	build-essential dkms git meson ninja-build
	# Ubuntu ships pkgconf now; "pkg-config" is only a transitional
	# package and is not necessarily installed even though the command is.
	"pkgconf|pkg-config|cmd:pkg-config"
	"linux-headers-$KVER"
)
LIBCAMERA_PKGS=(
	libyaml-dev libgnutls28-dev libegl-dev libgles-dev libgbm-dev
	libdrm-dev libudev-dev libevent-dev
	python3-jinja2 python3-ply python3-yaml python3-dev
)
RUNTIME_PKGS=(
	v4l2loopback-dkms v4l2loopback-utils v4l-utils
	gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good
	python3-pyqt6
)

case "$ACTION" in
install)
	need_root
	apt-get update -qq || warn "apt-get update failed, continuing with the current lists"
	apt_need "${BUILD_PKGS[@]}" "${LIBCAMERA_PKGS[@]}" "${RUNTIME_PKGS[@]}"
	ok "packages present"
	;;
uninstall)
	info "packages are left installed on purpose (they are shared with the rest of the system)"
	;;
check)
	missing=()
	for p in "${BUILD_PKGS[@]}" "${LIBCAMERA_PKGS[@]}" "${RUNTIME_PKGS[@]}"; do
		pkg_installed "$p" || missing+=("${p%%|*}")
	done
	if [ ${#missing[@]} -eq 0 ]; then
		report packages ok
	else
		report packages missing "${missing[*]}"
		exit 1
	fi
	;;
esac

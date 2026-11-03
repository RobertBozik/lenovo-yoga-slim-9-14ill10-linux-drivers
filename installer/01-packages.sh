#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# build dependencies
#
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if is_fedora; then
	BUILD_PKGS=(
		gcc gcc-c++ make dkms git meson ninja-build
		"pkgconf-pkg-config|cmd:pkg-config"
		mokutil openssl
	)
	# Separate: right after a dnf upgrade the running kernel's devel
	# package may be gone from the repositories, and it would take the
	# whole transaction down with it.
	KDEVEL="kernel-devel-$KVER"
	LIBCAMERA_PKGS=(
		libyaml-devel gnutls-devel mesa-libEGL-devel mesa-libgbm-devel
		libdrm-devel systemd-devel libevent-devel
		glib2-devel gstreamer1-devel gstreamer1-plugins-base-devel
		python3-jinja2 python3-ply python3-pyyaml python3-devel
	)
	RUNTIME_PKGS=(
		# v4l2loopback is in RPM Fusion Free, built by akmods.
		v4l2loopback akmod-v4l2loopback v4l-utils
		"gstreamer1|cmd:gst-launch-1.0" gstreamer1-plugins-base gstreamer1-plugins-good
		python3-pyqt6
		# soundmodes: the LSP plugins as LV2, and PipeWire's LV2 support.
		lsp-plugins-lv2 pipewire-module-filter-chain-lv2
	)
else
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
		# -Dgstreamer=enabled: the libcamerasrc element the feeder uses.
		libglib2.0-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
		python3-jinja2 python3-ply python3-yaml python3-dev
	)
	RUNTIME_PKGS=(
		v4l2loopback-dkms v4l2loopback-utils v4l-utils
		gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good
		python3-pyqt6
		# soundmodes: the LSP plugins as LV2, and PipeWire's LV2 support,
		# which Ubuntu ships apart from the other filter-graph plugins.
		lsp-plugins-lv2 libspa-0.2-modules-extra
	)
fi

AKMODS_CERT=/etc/pki/akmods/certs/public_key.der

# Fedora: v4l2loopback comes from RPM Fusion Free and is built by akmods,
# which signs with a key of its own - but only once that key exists, and
# akmods does not create it. Without it the module is unsigned, and with
# Secure Boot on it does not load.
fedora_repos() {
	rpm -q rpmfusion-free-release >/dev/null 2>&1 && return 0
	info "adding the RPM Fusion Free repository (v4l2loopback is packaged there)"
	dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
}

fedora_akmods() {
	local new=0
	if [ ! -e "$AKMODS_CERT" ]; then
		info "creating the akmods signing key"
		kmodgenca -a >/dev/null
		new=1
	fi
	if [ "$new" = 1 ] || [ -z "$(modinfo -k "$KVER" -F signer v4l2loopback 2>/dev/null)" ]; then
		info "building v4l2loopback for $KVER (akmods)"
		akmods --force --rebuild --kernels "$KVER" >/dev/null || warn "akmods failed - see /var/cache/akmods/"
	fi
	mok_enroll "$AKMODS_CERT" "v4l2loopback (akmods)"
}

case "$ACTION" in
install)
	need_root
	if is_fedora; then
		fedora_repos
		pkg_need "${BUILD_PKGS[@]}" "${LIBCAMERA_PKGS[@]}" "${RUNTIME_PKGS[@]}"
		pkg_need "$KDEVEL" ||
			die "$KDEVEL is not available - after a dnf upgrade, reboot into the new kernel and run this again"
		fedora_akmods
	else
		apt-get update -qq || warn "apt-get update failed, continuing with the current lists"
		pkg_need "${BUILD_PKGS[@]}" "${LIBCAMERA_PKGS[@]}" "${RUNTIME_PKGS[@]}"
	fi
	ok "packages present"
	;;
uninstall)
	info "packages are left installed on purpose (they are shared with the rest of the system)"
	;;
check)
	missing=()
	for p in "${BUILD_PKGS[@]}" "${LIBCAMERA_PKGS[@]}" "${RUNTIME_PKGS[@]}" ${KDEVEL:+"$KDEVEL"}; do
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

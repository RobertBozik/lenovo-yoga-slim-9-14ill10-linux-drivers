#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# libcamera with the OV32C4 patches, built into /usr/local
#
# The stock libcamera has no entry for this sensor and its software ISP
# lacks the pieces this camera needs (frame duration control, digital
# gain, temporal denoise, lens shading, zone statistics, skin metering).
# The patches in upstream/libcamera/ add them; every one is off unless
# the tuning file enables it, so the build stays close to upstream.
#
# The tree is pinned to the commit the patches were made against.
# /usr/local wins over the distribution libcamera at run time (ldconfig),
# and removing this step gives the machine its stock libcamera back.
#
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

UPSTREAM_URL="https://git.libcamera.org/libcamera/libcamera.git"
MIRROR_URL="https://github.com/libcamera-org/libcamera.git"
PIN="35c137c2f3e7104b96702c649344fafc91d8e233"   # see PIN_NOTE below
PIN_TAG="v0.7.2"
SRCDIR="${LIBCAMERA_SRC:-$TARGET_HOME/libcamera-ov32c4}"
BUILDDIR="$SRCDIR/build"
PREFIX=/usr/local
PATCHES="$REPO/upstream/libcamera"

# PIN_NOTE: the patches were developed against libcamera master of
# 2026-08-24 (0.7.2 + a few commits). If the pin no longer applies,
# LIBCAMERA_REF=<ref> overrides it and `git am` will tell you what broke.
REF="${LIBCAMERA_REF:-$PIN}"

install_libcamera() {
	need_root
	command -v meson >/dev/null || die "meson missing (step: packages)"

	if [ ! -d "$SRCDIR/.git" ]; then
		info "cloning libcamera into $SRCDIR"
		if ! as_user git clone -q "$UPSTREAM_URL" "$SRCDIR" 2>/dev/null; then
			warn "git.libcamera.org unreachable, using the GitHub mirror"
			as_user git clone -q "$MIRROR_URL" "$SRCDIR"
		fi
	fi

	as_user git -C "$SRCDIR" fetch -q --all || true
	if ! as_user git -C "$SRCDIR" rev-parse --verify -q "$REF^{commit}" >/dev/null; then
		warn "pinned commit not found, falling back to tag $PIN_TAG"
		REF="$PIN_TAG"
	fi

	info "checking out $REF"
	as_user git -C "$SRCDIR" am --abort 2>/dev/null || true
	as_user git -C "$SRCDIR" checkout -q --detach "$REF"

	patches=()
	for p in "$PATCHES"/[0-9]*.patch; do
		case "$p" in *cover-letter*) continue ;; esac
		patches+=("$p")
	done
	[ ${#patches[@]} -gt 0 ] || die "no patches found in $PATCHES"
	info "applying ${#patches[@]} patches"
	if ! as_user git -C "$SRCDIR" am -q "${patches[@]}"; then
		as_user git -C "$SRCDIR" am --abort || true
		die "the patches do not apply to $REF - set LIBCAMERA_REF to a matching commit"
	fi

	info "building (this takes a few minutes)"
	as_user meson setup "$BUILDDIR" "$SRCDIR" \
		--prefix="$PREFIX" --buildtype=release \
		-Dpipelines=simple -Dipas=softisp \
		-Dsoftisp-gpu=enabled \
		-Dcam=enabled -Dgstreamer=enabled \
		-Dqcam=disabled -Dlc-compliance=disabled -Ddocumentation=disabled \
		-Dtest=false -Dpycamera=disabled -Dv4l2=disabled \
		>/dev/null
	as_user ninja -C "$BUILDDIR" >/dev/null
	ninja -C "$BUILDDIR" install >/dev/null
	ldconfig
	ok "libcamera $(pkg-config --modversion libcamera 2>/dev/null || echo installed) in $PREFIX"
	info "GStreamer plugin: $(ls "$PREFIX"/lib/*/gstreamer-1.0/libgstlibcamera.so 2>/dev/null | head -1)"
}

case "$ACTION" in
install) install_libcamera ;;

uninstall)
	need_root
	if [ -d "$BUILDDIR" ]; then
		ninja -C "$BUILDDIR" uninstall >/dev/null 2>&1 || warn "ninja uninstall failed, removing by hand"
	fi
	rm -f "$PREFIX"/lib/*/libcamera*.so* "$PREFIX"/lib/*/gstreamer-1.0/libgstlibcamera.so
	rm -rf "$PREFIX"/lib/*/libcamera "$PREFIX"/share/libcamera "$PREFIX"/include/libcamera
	rm -f "$PREFIX"/bin/cam "$PREFIX"/lib/*/pkgconfig/libcamera*.pc
	ldconfig
	ok "removed libcamera from $PREFIX (the distribution one takes over again)"
	info "the source tree in $SRCDIR is left alone"
	;;

check)
	so="$(ls "$PREFIX"/lib/*/libcamera.so.* 2>/dev/null | head -1 || true)"
	if [ -n "$so" ]; then
		report libcamera ok "$so"
	else
		report libcamera missing "nothing in $PREFIX"
		exit 1
	fi
	# meson puts the IPA modules in <libdir>/libcamera/ipa/; older trees
	# put them straight into <libdir>/libcamera/, so look in both.
	ipa="$(find "$PREFIX"/lib -name 'ipa_softisp.so' -print -quit 2>/dev/null || true)"
	if [ -n "$ipa" ]; then
		report "softisp IPA" ok "$ipa"
	else
		report "softisp IPA" missing "no ipa_softisp.so under $PREFIX/lib"
	fi
	;;
esac

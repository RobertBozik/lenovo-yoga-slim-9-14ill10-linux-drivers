#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# speaker routing fixup for the ALC287 codec
#
# Out of the box only the tweeters play: pin 0x17 is connected to the
# wrong source, so the woofers stay silent and the volume control is not
# in the audible path. The kernel already has the right fixup
# (ALC287_FIXUP_YOGA9_14IAP7_BASS_SPK_PIN) but does not pick it for this
# machine, because the quirk table has no entry for PCI SSID 17aa:380b.
# Until that entry is upstream (bugzilla.kernel.org #221902), the model
# is forced by hand. On this laptop the parameter lives in
# snd_sof_intel_hda_generic - the codec is driven through SOF, not
# snd-hda-intel, so "options snd-hda-intel model=..." does nothing.
#
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CONF=/etc/modprobe.d/alc287-yoga9.conf
MODEL=alc287-yoga9-bass-spk-pin

case "$ACTION" in
install)
	need_root
	mod=snd_sof_intel_hda_generic
	if ! modinfo -p "$mod" 2>/dev/null | grep -q '^hda_model'; then
		if modinfo -p snd_sof_intel_hda_common 2>/dev/null | grep -q '^hda_model'; then
			mod=snd_sof_intel_hda_common
		else
			warn "no hda_model parameter found in the SOF modules of this kernel"
			warn "(checked snd_sof_intel_hda_generic and snd_sof_intel_hda_common)"
		fi
	fi
	printf 'options %s hda_model=%s\n' "$mod" "$MODEL" >/tmp/alc287-yoga9.conf
	install_file /tmp/alc287-yoga9.conf "$CONF"
	rm -f /tmp/alc287-yoga9.conf
	update-initramfs -u >/dev/null 2>&1 || warn "update-initramfs failed"
	ok "wrote $CONF (module $mod)"
	info "takes effect after a reboot"
	;;

uninstall)
	need_root
	remove_file "$CONF"
	update-initramfs -u >/dev/null 2>&1 || true
	;;

check)
	[ -f "$CONF" ] && report "audio modprobe.d" ok "$(cat "$CONF")" ||
		{ report "audio modprobe.d" missing; exit 1; }
	# "picked fixup ..." is a codec_dbg() message and does not appear in a
	# normal log, so ask the running kernel what the parameter actually is.
	found=""
	for m in snd_sof_intel_hda_generic snd_sof_intel_hda_common snd_hda_intel; do
		f="/sys/module/$m/parameters/hda_model"
		[ -r "$f" ] || continue
		v="$(cat "$f")"
		case "$v" in "" | "(null)" | "N/A") continue ;; esac
		found="$m=$v"
		[ "$v" = "$MODEL" ] && break
	done
	if [ "${found#*=}" = "$MODEL" ]; then
		report "model in this boot" ok "$found"
	elif [ -n "$found" ]; then
		report "model in this boot" missing "a different model is set: $found"
	else
		report "model in this boot" missing "not set (reboot pending?)"
	fi
	;;
esac

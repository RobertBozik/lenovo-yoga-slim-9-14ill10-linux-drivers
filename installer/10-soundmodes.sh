#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# sound modes for the speakers (Music, Movie, Game) from the Windows tuning
#
# Under Windows the speakers go through the vendor's processing, with a
# per-machine speaker correction and three modes on the key with the
# speaker and the gear. Without it the small speakers get no correction
# at all. The tuning is data in the Windows driver; tools/soundmodes/
# holds it converted into three PipeWire filter chains (see the README
# there for where the numbers come from). They are WirePlumber smart
# filters in front of the speaker sink, one enabled at a time (Music by
# default); the hotkeys step makes the key switch between them.
#
# The speakers stay the default output and carry the volume, so the
# volume keys work as before; the modes stay at 100 %. The filters are
# named in the language of the session, since Plasma lists them as
# virtual devices.
#
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SRC="$REPO/tools/soundmodes"
CONF_DIR=/etc/pipewire/pipewire.conf.d
DATA=/usr/local/share/yoga-soundmodes
MODES=(music movie game)
SPEAKER=alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Speaker__sink
# An earlier version put one output, "Speakers", in front of the modes.
OLD_FRONT_CONF="$CONF_DIR/89-yoga-soundmode.conf"

# "Speakers: Music" and so on, in the language of the session.
mode_title() {
	local lang="${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}"
	case "${lang%%_*}:$1" in
	sk:music) echo "Reproduktory: Hudba" ;; sk:movie) echo "Reproduktory: Film" ;;
	sk:game) echo "Reproduktory: Hra" ;;
	cs:music) echo "Reproduktory: Hudba" ;; cs:movie) echo "Reproduktory: Film" ;;
	cs:game) echo "Reproduktory: Hra" ;;
	de:music) echo "Lautsprecher: Musik" ;; de:movie) echo "Lautsprecher: Film" ;;
	de:game) echo "Lautsprecher: Spiel" ;;
	*:music) echo "Speakers: Music" ;; *:movie) echo "Speakers: Movie" ;;
	*:game) echo "Speakers: Game" ;;
	esac
}

restart_audio() {
	user_systemctl restart pipewire.service pipewire-pulse.service wireplumber.service
	sleep 2
}

# node.name -> id of a live PipeWire node, empty if there is none.
node_id() {
	as_user pw-dump 2>/dev/null | python3 -c '
import json, sys
name = sys.argv[1]
for o in json.load(sys.stdin):
    if o.get("type") == "PipeWire:Interface:Node" and \
       ((o.get("info") or {}).get("props") or {}).get("node.name") == name:
        print(o["id"])
        break
' "$1" 2>/dev/null || true
}

default_sink() {
	as_user wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null |
		sed -n 's/^[ *]*node\.name = "\(.*\)"$/\1/p' | head -1
}

volume_of() { [ -n "$1" ] && as_user wpctl get-volume "$1" 2>/dev/null | awk '{ print $2 }'; }
set_volume() { [ -n "$1" ] && as_user wpctl set-volume "$1" "$2" >/dev/null 2>&1 || true; }

case "$ACTION" in
install)
	need_root
	pkg_installed lsp-plugins-lv2 || die "lsp-plugins-lv2 missing (step: packages)"
	pkg_installed libspa-0.2-modules-extra || die "libspa-0.2-modules-extra missing (step: packages)"

	before="$(default_sink)"
	before_vol="$(volume_of "$(node_id "$before")" || true)"

	remove_file "$OLD_FRONT_CONF"
	for m in "${MODES[@]}"; do
		install_file "$SRC/$m.irs" "$DATA/$m.irs"
		tmp="$(mktemp)"
		sed "s|node.description = \"Speakers: [A-Za-z]*\"|node.description = \"$(mode_title "$m")\"|" \
			"$SRC/90-yoga-soundmode-$m.conf" >"$tmp"
		install_file "$tmp" "$CONF_DIR/90-yoga-soundmode-$m.conf"
		rm -f "$tmp"
	done
	restart_audio

	missing=()
	for m in "${MODES[@]}"; do
		[ -n "$(node_id "effect_input.yoga_soundmode_$m")" ] || missing+=("$m")
	done
	if [ ${#missing[@]} -gt 0 ]; then
		warn "not running yet: ${missing[*]} (no session, or see: journalctl --user -u pipewire)"
		exit 0
	fi

	# The speakers are the output; the modes are at 100 %. Earlier
	# versions made a mode the output and gave it the volume - that
	# volume goes to the speakers.
	spk="$(node_id "$SPEAKER")"
	case "$before" in
	effect_input.yoga_soundmode_* | yoga_soundmode)
		[ -n "$before_vol" ] && set_volume "$spk" "$before_vol"
		as_user wpctl set-default "$spk" && info "output set to the speakers"
		;;
	esac
	for m in "${MODES[@]}"; do
		set_volume "$(node_id "effect_input.yoga_soundmode_$m")" 1.0
	done
	# The hotkeys service enables the remembered mode when it starts.
	user_systemctl try-restart yoga-hotkeys.service
	ok "sound modes installed: ${MODES[*]}"
	;;

uninstall)
	need_root
	# Only if a mode was made the output by hand: the speakers again.
	case "$(default_sink)" in
	effect_input.yoga_soundmode_*)
		spk="$(node_id "$SPEAKER")"
		[ -n "$spk" ] && as_user wpctl set-default "$spk" >/dev/null 2>&1 || true
		;;
	esac
	remove_file "$OLD_FRONT_CONF"
	for m in "${MODES[@]}"; do
		remove_file "$CONF_DIR/90-yoga-soundmode-$m.conf"
		remove_file "$DATA/$m.irs"
	done
	rmdir "$DATA" 2>/dev/null || true
	restart_audio
	;;

check)
	for m in "${MODES[@]}"; do
		[ -f "$CONF_DIR/90-yoga-soundmode-$m.conf" ] && [ -f "$DATA/$m.irs" ] ||
			{ report "sound mode $m" missing; exit 1; }
		if [ -n "$(node_id "effect_input.yoga_soundmode_$m")" ]; then
			report "sound mode $m" ok
		else
			report "sound mode $m" missing "installed but not running (needs a session)"
		fi
	done
	cur="$(default_sink)"
	case "$cur" in
	"$SPEAKER") report "current output" ok "speakers" ;;
	"") report "current output" "n/a" "no session" ;;
	*) report "current output" "-" "$cur (modes apply to the speakers only)" ;;
	esac
	for m in "${MODES[@]}"; do
		v="$(volume_of "$(node_id "effect_input.yoga_soundmode_$m")" || true)"
		[ -z "$v" ] || [ "$v" = 1.00 ] || report "mode $m volume" "not 100%" "$v"
	done
	;;
esac

# SPDX-License-Identifier: GPL-2.0
# shellcheck shell=bash
# Shared helpers for the installer steps.
#
# Every step script is executed as:  bash installer/NN-name.sh ACTION
# with ACTION being install | uninstall | check, and with REPO, KVER,
# TARGET_USER, TARGET_HOME already exported by install.sh.

set -euo pipefail

: "${REPO:?}" "${KVER:?}" "${TARGET_USER:?}" "${TARGET_HOME:?}"

# BOLD is used by the step scripts, hence the export.
BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; OFF=$'\033[0m'
[ -t 1 ] || { BOLD=""; RED=""; GREEN=""; YELLOW=""; OFF=""; }
export BOLD

say()  { printf '%s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
ok()   { printf '  %s%s%s\n' "$GREEN" "$*" "$OFF"; }
warn() { printf '  %s%s%s\n' "$YELLOW" "$*" "$OFF" >&2; }
die()  { printf '%serror: %s%s\n' "$RED" "$*" "$OFF" >&2; exit 1; }

need_root() { [ "$(id -u)" = 0 ] || die "run with sudo"; }

# Run a command as the target (non-root) user, with a working user bus.
as_user() {
	local uid
	uid="$(id -u "$TARGET_USER")"
	sudo -u "$TARGET_USER" \
		XDG_RUNTIME_DIR="/run/user/$uid" \
		DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
		"$@"
}

# systemctl --user for the target user; never fails the whole install
# when there is no live session (e.g. running from a TTY or over ssh).
user_systemctl() {
	if as_user systemctl --user "$@" >/dev/null 2>&1; then
		return 0
	fi
	warn "systemctl --user $* did not work (no active session?);"
	warn "run it yourself after logging in."
	return 0
}

# Is a package requirement satisfied?  A requirement is one or more
# alternatives separated by "|"; an alternative of the form cmd:NAME is
# satisfied by the command NAME being on PATH.  This is for the packages
# distributions keep renaming - pkg-config is pkgconf on Ubuntu now, and
# the transitional package is not always installed.
pkg_installed() {
	local spec="$1" p
	local -a alts
	IFS='|' read -r -a alts <<<"$spec"
	for p in "${alts[@]}"; do
		case "$p" in
		cmd:*)
			if command -v "${p#cmd:}" >/dev/null 2>&1; then return 0; fi
			;;
		*)
			if dpkg-query -W -f='${Status}' "$p" 2>/dev/null |
				grep -q '^install ok installed$'; then return 0; fi
			;;
		esac
	done
	return 1
}

apt_need() {
	local missing=() spec
	for spec in "$@"; do
		if ! pkg_installed "$spec"; then
			# The first alternative is the one we install.
			missing+=("${spec%%|*}")
		fi
	done
	if [ ${#missing[@]} -gt 0 ]; then
		info "installing: ${missing[*]}"
		DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
	fi
}

# install_file SRC DEST MODE  - keeps a .bak of a foreign file it replaces
install_file() {
	local src="$1" dest="$2" mode="${3:-644}"
	if [ -e "$dest" ] && ! cmp -s "$src" "$dest" && [ ! -e "$dest.ov32c4.bak" ]; then
		cp -a "$dest" "$dest.ov32c4.bak"
		info "kept previous $dest as $dest.ov32c4.bak"
	fi
	install -D -m "$mode" "$src" "$dest"
}

remove_file() {
	local f="$1"
	[ -e "$f" ] || return 0
	rm -f "$f"
	info "removed $f"
	if [ -e "$f.ov32c4.bak" ]; then
		mv "$f.ov32c4.bak" "$f"
		info "restored $f from backup"
	fi
}

# check_report NAME OK_CONDITION_STRING - used by the check action
report() {
	local name="$1" state="$2" detail="${3:-}"
	case "$state" in
	ok)      printf '  %s%-28s ok%s   %s\n' "$GREEN" "$name" "$OFF" "$detail" ;;
	missing) printf '  %s%-28s MISSING%s %s\n' "$RED" "$name" "$OFF" "$detail" ;;
	*)       printf '  %s%-28s %s%s %s\n' "$YELLOW" "$name" "$state" "$OFF" "$detail" ;;
	esac
}

ACTION="${1:-install}"
case "$ACTION" in
install | uninstall | check) ;;
*) die "unknown action '$ACTION' (install|uninstall|check)" ;;
esac

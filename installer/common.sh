# SPDX-License-Identifier: GPL-2.0
# shellcheck shell=bash
# Shared helpers for the installer steps.
#
# Every step script is executed as:  bash installer/NN-name.sh ACTION
# with ACTION being install | uninstall | check, and with REPO, KVER,
# TARGET_USER, TARGET_HOME and PLATFORM already exported by install.sh.
#
# PLATFORM is the distribution and desktop the steps were written and
# tested for: "kubuntu" (Kubuntu, Plasma) or "fedora-gnome" (Fedora
# Workstation, GNOME). install.sh refuses anything else.

set -euo pipefail

: "${REPO:?}" "${KVER:?}" "${TARGET_USER:?}" "${TARGET_HOME:?}" "${PLATFORM:?}"

is_fedora() { [ "$PLATFORM" = fedora-gnome ]; }
is_gnome() { [ "$PLATFORM" = fedora-gnome ]; }

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
			# Fedora and other rpm-based systems
			if command -v rpm >/dev/null 2>&1 && rpm -q "$p" >/dev/null 2>&1; then return 0; fi
			;;
		esac
	done
	return 1
}

pkg_need() {
	local missing=() spec
	for spec in "$@"; do
		if ! pkg_installed "$spec"; then
			# The first alternative is the one we install.
			missing+=("${spec%%|*}")
		fi
	done
	[ ${#missing[@]} -gt 0 ] || return 0
	info "installing: ${missing[*]}"
	if is_fedora; then
		dnf install -y "${missing[@]}"
	else
		DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
	fi
}

# With Secure Boot on, a module signed with a key the firmware does not
# know is refused. Fedora's DKMS and akmods each make a key of their own
# on first use; it has to be enrolled once, through MokManager at the
# next boot. mok_enroll CERT WHAT queues that, unless it is already done
# or queued, or Secure Boot is off.
mok_enroll() {
	local cert="$1" what="$2"
	[ -f "$cert" ] || return 0
	command -v mokutil >/dev/null 2>&1 || return 0
	mokutil --sb-state 2>/dev/null | grep -q 'SecureBoot enabled' || return 0
	# "is already enrolled" or "is already in the enrollment request".
	# mokutil exits with 1 in both cases, so its output is read, not its
	# exit status (in a pipe, pipefail would turn that 1 into a failure).
	local out
	out="$(mokutil --test-key "$cert" 2>&1 || true)"
	case "$out" in *already*) return 0 ;; esac
	warn "Secure Boot: the key that signs $what is not enrolled yet."
	info "Choose a one-time password now. At the next boot a blue screen"
	info "(MokManager) comes up: Enroll MOK -> Continue -> Yes -> the password"
	info "-> Reboot. It uses the US keyboard layout (y and z swapped on a"
	info "Slovak or German keyboard)."
	if ! mokutil --import "$cert" </dev/tty; then
		warn "mokutil --import failed - run it yourself:"
		warn "  sudo mokutil --import $cert"
	fi
}

# GNOME: the Shell extension in tools/gnome-extension/ draws the camera
# mask and shows the hotkeys service's messages (steps mask and hotkeys).
# It goes to the system extension directory; whether it runs is a per-user
# setting. A new extension is picked up by GNOME at the next login.
GNOME_EXT_UUID=yoga-slim-9-14ill10@robertbozik.github.io
GNOME_EXT_DIR=/usr/share/gnome-shell/extensions/$GNOME_EXT_UUID
# The first test version of the mask extension, put in by hand.
GNOME_EXT_OLD=udc-mask@yoga-slim-9-14ill10

# gnome_ext_set enable|disable UUID - edit the user's enabled-extensions.
gnome_ext_set() {
	as_user python3 - "$1" "$2" <<'PY'
import ast
import subprocess
import sys

op, uuid = sys.argv[1:]


def get(key):
    out = subprocess.run(["gsettings", "get", "org.gnome.shell", key],
                         capture_output=True, text=True, check=True).stdout.strip()
    if out.startswith("@as "):
        out = out[4:]
    return list(ast.literal_eval(out))


def put(key, value):
    subprocess.run(["gsettings", "set", "org.gnome.shell", key, str(value)], check=True)


enabled, disabled = get("enabled-extensions"), get("disabled-extensions")
if op == "enable":
    if uuid not in enabled:
        enabled.append(uuid)
    disabled = [u for u in disabled if u != uuid]
else:
    enabled = [u for u in enabled if u != uuid]
put("enabled-extensions", enabled)
put("disabled-extensions", disabled)
PY
}

gnome_ext_enabled() {
	as_user gsettings get org.gnome.shell enabled-extensions 2>/dev/null | grep -F "'$1'" >/dev/null
}

gnome_ext_install() {
	install_file "$REPO/tools/gnome-extension/metadata.json" "$GNOME_EXT_DIR/metadata.json"
	install_file "$REPO/tools/gnome-extension/extension.js" "$GNOME_EXT_DIR/extension.js"
	if [ -d "$TARGET_HOME/.local/share/gnome-shell/extensions/$GNOME_EXT_OLD" ]; then
		gnome_ext_set disable "$GNOME_EXT_OLD" || true
		rm -rf "$TARGET_HOME/.local/share/gnome-shell/extensions/$GNOME_EXT_OLD"
		info "removed the test extension $GNOME_EXT_OLD"
	fi
	if gnome_ext_set enable "$GNOME_EXT_UUID"; then
		ok "GNOME Shell extension $GNOME_EXT_UUID enabled (runs from the next login)"
	else
		warn "could not enable the GNOME Shell extension (no session?) - after logging in:"
		warn "  gnome-extensions enable $GNOME_EXT_UUID"
	fi
}

gnome_ext_remove() {
	gnome_ext_set disable "$GNOME_EXT_UUID" || true
	remove_file "$GNOME_EXT_DIR/metadata.json"
	remove_file "$GNOME_EXT_DIR/extension.js"
	rmdir "$GNOME_EXT_DIR" 2>/dev/null || true
}

gnome_ext_check() {
	if [ -f "$GNOME_EXT_DIR/extension.js" ] && gnome_ext_enabled "$GNOME_EXT_UUID"; then
		report "GNOME extension" ok "$GNOME_EXT_UUID"
	elif [ -f "$GNOME_EXT_DIR/extension.js" ]; then
		report "GNOME extension" missing "installed but not enabled"
	else
		report "GNOME extension" missing "$GNOME_EXT_DIR"
	fi
}

# Every file install_file writes is recorded here with its hash, so that
# a later run can tell our own older copy (after a git pull) from a file
# somebody else put there. Without it the older copy was taken for a
# foreign file, kept as .bak, and put back by the uninstall.
MANIFEST="${OV32C4_MANIFEST:-/var/lib/ov32c4-installer/installed}"

manifest_hash() {
	[ -f "$MANIFEST" ] || return 0
	awk -v p="$1" '$2 == p { h = $1 } END { if (h != "") print h }' "$MANIFEST"
}

manifest_forget() {
	[ -f "$MANIFEST" ] || return 0
	awk -v p="$1" '$2 != p' "$MANIFEST" >"$MANIFEST.tmp"
	mv "$MANIFEST.tmp" "$MANIFEST"
}

manifest_record() {
	manifest_forget "$1"
	mkdir -p "$(dirname "$MANIFEST")"
	sha256sum "$1" >>"$MANIFEST"
}

# install_file SRC DEST MODE  - keeps a .bak of a foreign file it replaces
install_file() {
	local src="$1" dest="$2" mode="${3:-644}" ours
	if [ -e "$dest" ] && ! cmp -s "$src" "$dest" && [ ! -e "$dest.ov32c4.bak" ]; then
		ours="$(manifest_hash "$dest")"
		if [ -n "$ours" ] && [ "$ours" = "$(sha256sum "$dest" | cut -d' ' -f1)" ]; then
			info "updating $dest"
		else
			cp -a "$dest" "$dest.ov32c4.bak"
			info "kept previous $dest as $dest.ov32c4.bak"
		fi
	fi
	install -D -m "$mode" "$src" "$dest"
	manifest_record "$dest"
}

remove_file() {
	local f="$1"
	manifest_forget "$f"
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

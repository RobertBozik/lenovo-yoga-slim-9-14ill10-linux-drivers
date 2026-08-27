#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Undo what install.sh did, in reverse order.
#
#   sudo bash uninstall.sh              # everything
#   sudo bash uninstall.sh --step mask  # one step
#
# What is deliberately left behind: the packages installed from the
# distribution (they are shared with the rest of the system), the
# libcamera source tree, the mask calibration in ~/.config, and the
# video/kvm group membership.
#
set -euo pipefail
exec bash "$(dirname "${BASH_SOURCE[0]}")/install.sh" --uninstall "$@"

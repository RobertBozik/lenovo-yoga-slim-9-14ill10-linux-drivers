#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Black mask over the lens of an under-display camera.

The Lenovo Yoga Slim 9 14ILL10 has its camera under the OLED panel. When
the panel above the lens is lit, its own light goes straight into the
optics: the picture gets a veil, loses contrast, and the panel's pixel
grid becomes visible in it. Windows deals with this by blanking that
piece of the panel while the camera is in use - ov32c4.sys carries an
IsSupportCameraMask flag for it, but the drawing itself is done by a
separate CVF driver on the display side. On Linux nothing does it.

This program replaces that from userspace: while the sensor is
streaming, it holds a black dot over the lens. Black on OLED means the
pixels are off, so as far as the camera is concerned the result is the
same.

    python3 scripts/udc-mask.py --calibrate     # find where the lens is
    python3 scripts/udc-mask.py --test          # show the mask for 10 s
    python3 scripts/udc-mask.py                 # run in the background
    python3 scripts/udc-mask.py --install-service

The position is saved in ~/.config/udc-mask.json.

Streaming is detected through the privacy LED. The v4l2 core turns that
LED on and off around enable_streams/disable_streams, so it says exactly
what we need to know: whether the sensor is transferring frames.

Runtime PM (power/runtime_status) looks like the obvious source but is
not: it reports power, not streaming. Measured on this machine: status
"active", usage 1, with the LED dark and nobody capturing. Looking for
who has /dev/video* open is no good either - with libcamera the client
is pipewire itself, which keeps the file open between uses.

A note on Wayland: a client there may not place its own window, so the
mask runs through XWayland as an override-redirect window
(X11BypassWindowManagerHint). That is why QT_QPA_PLATFORM=xcb is set
before Qt is imported.
"""

import argparse
import glob
import json
import os
import signal
import socket
import sys
import time

# Must come before importing Qt: on Wayland the window cannot be placed.
os.environ.setdefault("QT_QPA_PLATFORM", "xcb")

from PyQt6.QtCore import Qt, QTimer, QRect  # noqa: E402
from PyQt6.QtGui import QColor, QPainter  # noqa: E402
from PyQt6.QtWidgets import QApplication, QWidget  # noqa: E402

CONFIG = os.path.expanduser("~/.config/udc-mask.json")
LED_GLOB = "/sys/class/leds/*OVTI32C4*privacy*/brightness"
# State from the loopback watcher (tools/loopback/ov32c4-camera-watch):
# "feeder=0/1 readers=N".  While the feeder runs the mask follows the
# readers - after the last one leaves the feeder still runs out its grace
# period, but nobody is watching, so the mask goes away at once.  Before
# the feeder starts, readers=1 brings the mask up earlier than the sensor
# starts capturing.  With no watcher (a direct libcamera client, e.g. a
# browser started with the right flag) the privacy LED decides.
STATE_FILE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
                          "ov32c4-camera-state")
# Changing the desktop scaling moves the dot off the lens, and a running
# process cannot see it coming: measured on Plasma 6.6, going from 210 %
# to 225 % leaves QScreen.geometry(), devicePixelRatio() and
# logicalDotsPerInch() all reporting the values they had at startup, and
# geometryChanged never fires.  Recomputing the position is therefore
# useless - the inputs are stale, not the arithmetic.  What does change is
# this file, which the compositor rewrites when the output configuration
# is applied, so the mask watches it and re-executes itself to get a fresh
# look at the screen.  Where the file does not exist nothing is watched
# and the position holds until the service is restarted by hand.
DISPLAY_CONFIG = os.path.expanduser("~/.config/kwinoutputconfig.json")
# Applying a new mode takes a moment and rewrites the file more than once.
RESTART_SETTLE = 1.5
POLL_MS = 100
# The position is PHYSICAL (mm), not in pixels: the dot is horizontally
# centred on the panel (offset dx_mm), dy_mm from the top edge, diameter
# d_mm.  Pixels are computed from the panel size in the EDID and from the
# screen Qt reports.  That arithmetic is right but it is only as fresh as
# Qt's idea of the screen, which is why the scale change is handled by the
# restart above and not by recomputing in place (measured: 210 % -> 225 %
# moved the dot by about a centimetre and nothing recomputed it).
DEFAULT = {"dx_mm": 0.0, "dy_mm": 1.0, "d_mm": 12.0, "calibrated": False}
EDID_GLOB = "/sys/class/drm/card*-eDP-*/edid"

SERVICE = """[Unit]
Description=Black mask over the under-display camera lens
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart={exe} {script}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
"""


def display_stamp():
    """Something that changes when the output configuration changes."""
    try:
        st = os.stat(DISPLAY_CONFIG)
        return st.st_mtime_ns, st.st_size
    except OSError:
        return None


def load_config():
    cfg = dict(DEFAULT)
    try:
        with open(CONFIG) as f:
            cfg.update(json.load(f))
    except (OSError, ValueError):
        pass
    return cfg


def save_config(cfg):
    cfg["calibrated"] = True
    os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
    with open(CONFIG, "w") as f:
        json.dump(cfg, f, indent=2)
    print("saved to %s: %s" % (CONFIG, cfg))


def panel_size_mm():
    """Panel (width, height) in mm from the EDID, or None.

    Read straight out of sysfs, because XWayland reports a physical
    screen size invented to make the result come out at 96 dpi.
    """
    for path in sorted(glob.glob(EDID_GLOB)):
        try:
            with open(path, "rb") as f:
                edid = f.read()
        except OSError:
            continue
        if len(edid) < 128:
            continue
        w = ((edid[68] >> 4) << 8) | edid[66]
        h = ((edid[68] & 0x0F) << 8) | edid[67]
        if w and h:
            return w, h
    return None


def geometry_px(cfg):
    """(x, y, d) of the dot in pixels of the current screen, from the mm."""
    scr = QApplication.primaryScreen().geometry()
    size = panel_size_mm()
    if size is None:
        phys = QApplication.primaryScreen().physicalSize()
        size = (phys.width(), phys.height())
        print("no EDID found, using Qt's physical size (may be wrong): %s" % (size,))
    w_mm, h_mm = size
    kx = scr.width() / float(w_mm)
    ky = scr.height() / float(h_mm)
    d = int(round(cfg["d_mm"] * kx))
    x = int(round(scr.width() / 2.0 + cfg["dx_mm"] * kx - d / 2.0))
    y = int(round(cfg["dy_mm"] * ky))
    return x, y, d


def x_socket_ready():
    """Can we actually connect to the X server in DISPLAY?

    DISPLAY being set is not enough - at session start it tends to be set
    before XWayland is listening.  So connect to its unix socket for real.
    """
    disp = os.environ.get("DISPLAY")
    if not disp:
        return False
    host, _, num = disp.rpartition(":")
    if host:
        return True         # remote display, the socket cannot be checked
    path = "/tmp/.X11-unix/X" + num.split(".")[0]
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.settimeout(1.0)
        s.connect(path)
        return True
    except OSError:
        return False
    finally:
        s.close()


def wait_for_display(timeout=60):
    """Wait for the display; give up with an error if it never comes.

    Qt does not ask about a missing display - it calls abort() and the
    process dies with a core dump.  Started from systemd that happens
    every time the service comes up before XWayland.  So do not leave it
    to Qt: either the display appears, or we exit cleanly and
    Restart=on-failure tries again shortly.
    """
    for _ in range(timeout):
        if x_socket_ready():
            return
        time.sleep(1)
    sys.exit("no display after %d s, giving up (systemd will retry)" % timeout)


def find_led():
    """Path to the privacy LED's brightness, or None."""
    hits = glob.glob(LED_GLOB)
    return hits[0] if hits else None


def camera_active(led):
    """True while the sensor is streaming.  With no LED, draw nothing."""
    if led is None:
        return False
    try:
        with open(led) as f:
            return int(f.read().strip()) > 0
    except (OSError, ValueError):
        return False


def loopback_state():
    """(feeder_running, readers) from the watcher, or None if no file."""
    try:
        with open(STATE_FILE) as f:
            txt = f.read()
    except OSError:
        return None
    feeder, readers = False, 0
    for tok in txt.split():
        k, _, v = tok.partition("=")
        if k == "feeder":
            feeder = v == "1"
        elif k == "readers":
            readers = int(v)
    return feeder, readers


def mask_wanted(led):
    state = loopback_state()
    if state is not None:
        feeder, readers = state
        # The dot is up whenever the sensor is capturing, which includes
        # the feeder's grace period after the last reader left.  It used to
        # go away as soon as nobody was watching, which looked tidier and
        # was wrong twice over: the sensor keeps capturing through an
        # uncovered lens, and an application that reopens the node during
        # the grace period gets a frame at once - the feeder is already
        # writing them - while the mask still needs a poll and a window
        # map.  Measured: about 90 ms, which is two or three frames of the
        # panel's own pixels at the start of every warm restart.
        if feeder or readers > 0:
            return True
    return camera_active(led)


class Mask(QWidget):
    """A black dot that takes no input and stays on top."""

    def __init__(self, cfg):
        super().__init__(None,
                         Qt.WindowType.FramelessWindowHint |
                         Qt.WindowType.WindowStaysOnTopHint |
                         Qt.WindowType.Tool |
                         Qt.WindowType.WindowTransparentForInput |
                         Qt.WindowType.X11BypassWindowManagerHint)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.apply(cfg)

    def apply(self, cfg):
        # No setMask(): a QRegion mask has jagged edges, there is no
        # antialiasing.  The window is transparent instead and the circle
        # is drawn smooth in paintEvent.
        x, y, d = geometry_px(cfg)
        self.setGeometry(x, y, d, d)

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QColor(0, 0, 0))
        p.drawEllipse(self.rect())


class Calibrator(QWidget):
    """A white screen with a black dot the arrow keys move.

    White is deliberately the worst case - that is when the glare is
    strongest, so the moment the dot lands on the lens is obvious in a
    live preview.
    """

    def __init__(self, cfg):
        super().__init__()
        self.cfg = dict(DEFAULT)
        self.cfg.update({k: cfg[k] for k in ("dx_mm", "dy_mm", "d_mm") if k in cfg})
        self.setWindowTitle("udc-mask calibration")
        self.showFullScreen()

    def keyPressEvent(self, e):
        step = 1.0 if e.modifiers() & Qt.KeyboardModifier.ShiftModifier else 0.2
        k = e.key()
        if k == Qt.Key.Key_Left:
            self.cfg["dx_mm"] -= step
        elif k == Qt.Key.Key_Right:
            self.cfg["dx_mm"] += step
        elif k == Qt.Key.Key_Up:
            self.cfg["dy_mm"] = max(0.0, self.cfg["dy_mm"] - step)
        elif k == Qt.Key.Key_Down:
            self.cfg["dy_mm"] += step
        elif k in (Qt.Key.Key_Plus, Qt.Key.Key_Equal):
            self.cfg["d_mm"] += 0.5
        elif k == Qt.Key.Key_Minus:
            self.cfg["d_mm"] = max(2.0, self.cfg["d_mm"] - 0.5)
        elif k in (Qt.Key.Key_Return, Qt.Key.Key_Enter):
            save_config(self.cfg)
            QApplication.quit()
            return
        elif k == Qt.Key.Key_Escape:
            print("cancelled, nothing saved")
            QApplication.quit()
            return
        else:
            return
        self.update()

    def paintEvent(self, _):
        p = QPainter(self)
        p.fillRect(self.rect(), QColor(255, 255, 255))
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QColor(0, 0, 0))
        x, y, d = geometry_px(self.cfg)
        p.drawEllipse(QRect(x, y, d, d))

        p.setPen(QColor(0, 0, 0))
        p.drawText(40, self.height() - 120,
                   "Arrow keys move the dot by 0.2 mm (Shift = 1 mm), "
                   "+/- change the diameter by 0.5 mm.")
        p.drawText(40, self.height() - 90,
                   "Watch a live camera preview in another window.  When the "
                   "picture clears up, the dot is over the lens.")
        p.drawText(40, self.height() - 60,
                   "Enter saves, Esc cancels.    from centre %+.1f mm, from top "
                   "%.1f mm, diameter %.1f mm  (%d,%d px, %d px)"
                   % (self.cfg["dx_mm"], self.cfg["dy_mm"], self.cfg["d_mm"], x, y, d))


def run_daemon(cfg):
    if not cfg.get("calibrated") or "d_mm" not in cfg:
        sys.exit("the position is not set (or is from an older version that "
                 "stored pixels); run: udc-mask.py --calibrate")

    wait_for_display()

    led = find_led()
    if led is None:
        sys.exit("no privacy LED found (%s) - are the ov32c4 and INT3472 "
                 "drivers loaded?" % LED_GLOB)

    # Qt installs its own handler and then ignores Ctrl+C in the event
    # loop; without this the daemon can only be killed from another shell.
    signal.signal(signal.SIGINT, signal.SIG_DFL)

    app = QApplication(sys.argv)
    mask = Mask(cfg)
    state = {"on": False, "display": display_stamp(), "changed_at": None}
    app.primaryScreen().geometryChanged.connect(lambda _: mask.apply(cfg))

    def tick():
        stamp = display_stamp()
        if stamp != state["display"]:
            state["display"] = stamp
            state["changed_at"] = time.monotonic()
        if (state["changed_at"] is not None and
                time.monotonic() - state["changed_at"] > RESTART_SETTLE):
            print("display configuration changed, restarting", flush=True)
            os.execv(sys.executable, [sys.executable] + sys.argv)

        on = mask_wanted(led)
        if on == state["on"]:
            return
        state["on"] = on
        if on:
            mask.show()
            mask.raise_()
        else:
            mask.hide()

    t = QTimer()
    t.timeout.connect(tick)
    t.start(POLL_MS)

    print("running, watching %s (Ctrl+C to stop)" % led)
    sys.exit(app.exec())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--calibrate", action="store_true",
                    help="find where the lens is (white screen, arrow keys, Enter)")
    ap.add_argument("--test", action="store_true",
                    help="show the mask for ten seconds and exit")
    ap.add_argument("--install-service", action="store_true",
                    help="write a systemd user service and enable it "
                         "(install.sh --step mask does this for you)")
    args = ap.parse_args()

    cfg = load_config()

    if args.install_service:
        path = os.path.expanduser("~/.config/systemd/user/udc-mask.service")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(SERVICE.format(exe=sys.executable,
                                   script=os.path.abspath(__file__)))
        print("written: %s" % path)
        print("enable it: systemctl --user daemon-reload && "
              "systemctl --user enable --now udc-mask")
        return

    if args.calibrate:
        app = QApplication(sys.argv)
        w = Calibrator(cfg)
        w.show()
        sys.exit(app.exec())

    if args.test:
        if not cfg.get("calibrated") or "d_mm" not in cfg:
            sys.exit("the position is not set, run --calibrate first")
        app = QApplication(sys.argv)
        m = Mask(cfg)
        m.show()
        QTimer.singleShot(10000, app.quit)
        sys.exit(app.exec())

    run_daemon(cfg)


if __name__ == "__main__":
    main()

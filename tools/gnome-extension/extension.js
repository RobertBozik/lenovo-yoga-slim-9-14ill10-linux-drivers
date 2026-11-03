// SPDX-License-Identifier: GPL-2.0
//
// GNOME Shell extension for the Lenovo Yoga Slim 9 14ILL10 (83CX), installed
// by install.sh --step mask on GNOME. Three things the hotkeys service and
// the camera need from the Shell itself:
//
// 1. Black dot over the under-display camera lens, drawn by GNOME Shell
// itself. An ordinary window - even an always-on-top one - stays below
// the Shell's own UI (screenshot tool, overview, panel), so on GNOME the
// mask has to be an actor on the stage, above everything else.
//
// Same inputs as scripts/udc-mask.py: the privacy LED says whether the
// sensor streams, ~/.config/udc-mask.json says where the lens is (in mm),
// the EDID gives the panel size in mm.
//
// 2. The on-screen messages of the hotkeys service
// (tools/hotkeys/yoga-hotkeys) as a GNOME OSD - the same bubble as the
// volume keys - through a small D-Bus method on the Shell's connection:
//   busctl --user call org.gnome.Shell /io/github/RobertBozik/YogaOsd \
//       io.github.RobertBozik.YogaOsd ShowText ss <icon> <text>
// GNOME's own ShowOSD is only open to gnome-settings-daemon.
//
// 3. The brightness slider (GetBrightness/SetBrightness), so that the
// hotkeys service can dim the screen in power-saver mode like Windows.

import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const POLL_MS = 100;
const LED_RETRY_TICKS = 50;   // look for the LED again every 5 s
const DEFAULT = {dx_mm: 0, dy_mm: 1, d_mm: 12};
const OSD_PATH = '/io/github/RobertBozik/YogaOsd';
const OSD_XML = `<node>
  <interface name="io.github.RobertBozik.YogaOsd">
    <method name="ShowText">
      <arg type="s" direction="in" name="icon"/>
      <arg type="s" direction="in" name="text"/>
    </method>
    <method name="GetBrightness">
      <arg type="d" direction="out" name="value"/>
    </method>
    <method name="SetBrightness">
      <arg type="d" direction="in" name="value"/>
    </method>
  </interface>
</node>`;

function readBytes(path) {
    try {
        const [ok, bytes] = GLib.file_get_contents(path);
        return ok ? bytes : null;
    } catch (e) {
        return null;
    }
}

function listDir(path) {
    const names = [];
    try {
        const en = Gio.File.new_for_path(path).enumerate_children(
            'standard::name', Gio.FileQueryInfoFlags.NONE, null);
        let info;
        while ((info = en.next_file(null)) !== null)
            names.push(info.get_name());
        en.close(null);
    } catch (e) {
        // not there
    }
    return names;
}

function findLed() {
    const n = listDir('/sys/class/leds').find(
        x => x.includes('OVTI32C4') && x.includes('privacy'));
    return n ? `/sys/class/leds/${n}/brightness` : null;
}

// Connector name and physical size of the built-in panel (EDID detailed
// timing descriptor, bytes 66-68).
function findPanel() {
    for (const n of listDir('/sys/class/drm').sort()) {
        const m = n.match(/^card\d+-(eDP-\d+)$/);
        if (!m)
            continue;
        const e = readBytes(`/sys/class/drm/${n}/edid`);
        if (!e || e.length < 128)
            continue;
        const w = ((e[68] >> 4) << 8) | e[66];
        const h = ((e[68] & 0x0f) << 8) | e[67];
        if (w && h)
            return {connector: m[1], wMm: w, hMm: h};
    }
    return null;
}

function loadConfig() {
    const cfg = {...DEFAULT};
    const b = readBytes(GLib.build_filenamev([GLib.get_user_config_dir(), 'udc-mask.json']));
    if (b) {
        try {
            Object.assign(cfg, JSON.parse(new TextDecoder().decode(b)));
        } catch (e) {
            // keep the defaults
        }
    }
    return cfg;
}

export default class YogaSlim9Extension extends Extension {
    enable() {
        this._panel = findPanel();
        this._led = findLed();
        this._ticks = 0;
        this._dot = new St.Widget({reactive: false, can_focus: false, visible: false});
        global.stage.add_child(this._dot);
        this._monitorsId = Main.layoutManager.connect('monitors-changed', () => this._place());
        this._timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, POLL_MS, () => {
            this._tick();
            return GLib.SOURCE_CONTINUE;
        });
        this._osd = Gio.DBusExportedObject.wrapJSObject(OSD_XML, this);
        this._osd.export(Gio.DBus.session, OSD_PATH);
    }

    // D-Bus: a message without a level bar, on every monitor.
    ShowText(icon, text) {
        Main.osdWindowManager.showAll(Gio.ThemedIcon.new(icon), text, null, null);
    }

    // D-Bus: GNOME's brightness slider, 0..1 (-1: no brightness control).
    // Used by the hotkeys service to dim the screen in power-saver mode.
    GetBrightness() {
        const scale = Main.brightnessManager?.globalScale;
        return scale ? scale.value : -1;
    }

    // Silently, like Plasma's setBrightnessSilent: the brightness manager
    // shows its OSD synchronously from the value change (GNOME 51,
    // brightnessManager.js _showOSD), so the OSD is off for that moment.
    SetBrightness(value) {
        const scale = Main.brightnessManager?.globalScale;
        if (!scale)
            return;
        const osd = Main.osdWindowManager;
        const show = osd.show;
        osd.show = () => {};
        try {
            scale.value = Math.max(0, Math.min(1, value));
        } finally {
            osd.show = show;
        }
    }

    disable() {
        this._osd?.unexport();
        this._osd = null;
        if (this._timer)
            GLib.source_remove(this._timer);
        this._timer = 0;
        if (this._monitorsId)
            Main.layoutManager.disconnect(this._monitorsId);
        this._monitorsId = 0;
        this._dot?.destroy();
        this._dot = null;
    }

    _streaming() {
        if (!this._led) {
            if (this._ticks++ % LED_RETRY_TICKS)
                return false;
            this._led = findLed();
            if (!this._led)
                return false;
        }
        const b = readBytes(this._led);
        return b !== null && parseInt(new TextDecoder().decode(b), 10) > 0;
    }

    _tick() {
        const on = this._streaming() && this._panel !== null;
        if (on && !this._dot.visible) {
            this._place();      // re-read the calibration every time
            this._dot.show();
        } else if (!on && this._dot.visible) {
            this._dot.hide();
        }
        // Stay the topmost child of the stage, above whatever the Shell
        // added since (screenshot UI, notifications, ...).
        if (this._dot.visible && global.stage.get_last_child() !== this._dot)
            global.stage.set_child_above_sibling(this._dot, null);
    }

    _place() {
        if (!this._panel)
            return;
        const mm = global.backend.get_monitor_manager();
        const idx = mm.get_monitor_for_connector(this._panel.connector);
        const mon = Main.layoutManager.monitors[idx] ?? Main.layoutManager.primaryMonitor;
        if (!mon)
            return;
        const cfg = loadConfig();
        const kx = mon.width / this._panel.wMm;
        const ky = mon.height / this._panel.hMm;
        const d = Math.max(1, Math.round(cfg.d_mm * kx));
        const x = Math.round(mon.x + mon.width / 2 + cfg.dx_mm * kx - d / 2);
        const y = Math.round(mon.y + cfg.dy_mm * ky);
        this._dot.set_position(x, y);
        this._dot.set_size(d, d);
        this._dot.set_style(`background-color: black; border-radius: ${d / 2}px;`);
    }
}

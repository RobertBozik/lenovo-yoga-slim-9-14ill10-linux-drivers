# Lenovo Yoga Slim 9 14ILL10 (83CX) on Linux — OmniVision OV32C4 webcam driver, ALC287 speaker fix, Xe display fix

Three things do not work on this laptop under Linux out of the box: the
webcam does not exist at all, only the tweeters play, and the screen
blanks for a moment during video calls. This repository fixes all three.

Clone it, run one command, reboot.

```sh
git clone https://github.com/RobertBozik/lenovo-yoga-slim-9-14ill10-ov32c4-linux.git
cd lenovo-yoga-slim-9-14ill10-ov32c4-linux
sudo bash install.sh
sudo reboot
```

After the reboot, `sudo bash install.sh --check` should report `ok` on
every line, and the camera shows up in ordinary applications — browsers,
Zoom, Viber, Cheese — as **Lenovo OV32C4**.

Nothing is downloaded from anywhere except the distribution's own
packages and the libcamera source tree. Everything else is in this
repository.

---

## The machine

| | |
|---|---|
| Model | Lenovo Yoga Slim 9 14ILL10, machine type **83CX** |
| SoC | Intel Core Ultra 7 258V (Lunar Lake), Xe2 graphics, **IPU7** |
| Camera | **OmniVision OV32C4**, ACPI `OVTI32C4`, under the OLED panel |
| Audio codec | Realtek **ALC287**, driven through SOF |
| Developed and tested on | Kubuntu 26.04, kernel 7.0.0-30-generic |

Other Lunar Lake laptops with the same sensor may work; the installer
warns if the DMI strings do not match and lets you continue anyway.

## What you get

**A camera that works.** There was no driver for this sensor anywhere,
so there is one here: `src/ov32c4.c`, written from the sensor's register
tables, with the modes, exposure, analogue and digital gain, and the
flips the pipeline needs. It is submitted upstream (see below), and
until it is merged it is built out of tree by DKMS, so a kernel update
does not take your camera away.

**A picture worth using.** The Intel IPU7 has no open image processing
stack, so the picture is produced by libcamera's software ISP. Out of
the box that ISP is fairly basic, so this repository carries nineteen
patches for it (`upstream/libcamera/`) and a tuning file measured on this
camera (`tuning/ov32c4.yaml`): lens shading correction, highlight
protection, a linear toe at black, subtraction of the veil the OLED panel
scatters into the lens, temporal denoise, zone statistics, and metering
that finds the face rather than the window behind it.

**The camera visible to every application.** Programs that speak plain
V4L2 cannot see a libcamera-only camera, so a `v4l2loopback` node
`/dev/video42` called "Lenovo OV32C4" is created and fed from libcamera
whenever something opens it (`tools/loopback/`). A WirePlumber rule hides
the loopback from PipeWire applications so the camera is not offered
twice.

**A black dot over the lens.** The sensor sits *under* the display. When
the pixels directly above the lens are lit, their own light goes into it:
the picture loses contrast and the panel's pixel grid becomes visible in
it. A small always-on-top window blanks that spot while the camera
streams (`scripts/udc-mask.py`). Black on OLED means the pixels are off,
so the lens sees nothing. Calibrate the position once:

```sh
python3 /usr/local/bin/udc-mask.py --calibrate
```

**Both speakers.** Out of the box pin `0x17` is connected to the wrong
source: the woofers stay silent and the volume control is not even in the
audible path. The kernel already has the right fixup but does not pick it
for this machine, because its quirk table has no entry for PCI SSID
`17aa:380b`. Until that entry is upstream
([bugzilla #221902](https://bugzilla.kernel.org/show_bug.cgi?id=221902))
the model is forced by hand.

**A screen that stops blanking.** Panel self-refresh and panel replay are
disabled for the Xe driver through the kernel command line. The cost is a
little more power when the screen is idle.

## The installer

Eight independent steps. Each one can install, uninstall and check
itself, and can be run again at any time.

```sh
sudo bash install.sh --list           # what the steps are
sudo bash install.sh                  # all of them
sudo bash install.sh --step mask      # just one
sudo bash install.sh --skip libcamera # all but one
sudo bash install.sh --check          # change nothing, report what is installed
sudo bash uninstall.sh                # put the machine back
```

| step | what it does |
|---|---|
| `packages` | build dependencies and runtime packages |
| `driver` | `ov32c4` and the patched `ipu-bridge`, built by DKMS |
| `libcamera` | libcamera with the patches in `upstream/libcamera/`, into `/usr/local` |
| `tuning` | the software ISP tuning file for this sensor |
| `loopback` | `/dev/video42`, the feeder service and the WirePlumber rule |
| `mask` | the black dot over the lens |
| `audio` | the ALC287 speaker routing fixup |
| `graphics` | the Xe kernel parameters |

The `libcamera` step clones libcamera, checks out the commit the patches
were made against, applies them and builds into `/usr/local`. It takes
ten to fifteen minutes and leaves the source tree in
`~/libcamera-ov32c4`. Removing this step gives you the distribution's
libcamera back.

A file that was already there and is not ours is kept as
`<name>.ov32c4.bak` and put back on uninstall.

## Known limitations

* **Secure Boot has to be off.** Not because of the modules — DKMS signs
  them with the machine's MOK — but because this machine's firmware does
  not accept the shim at all; with Secure Boot on, Linux does not boot.
* **In very low light the picture is noisy** and can pick up a colour
  cast. At that point the ISP is running at high digital gain and the
  sensor is small; this is the limit of the hardware more than of the
  tuning.
* **One owner at a time.** If a PipeWire client holds the camera through
  libcamera directly, the loopback feeder cannot start, and the other way
  round. Details in `tools/loopback/README.md`.
* **Reported colour temperature is wrong.** libcamera's generic
  sensor-to-XYZ matrix compresses the range; the picture is right, the
  `ColourTemperature` metadata is not.

## Upstream

The kernel side is on its way in. The series — device tree bindings,
the sensor driver, and the one-line `ipu-bridge` entry — was posted to
linux-media on 2026-08-26
([lore](https://lore.kernel.org/linux-media/20260826072002.14357-1-robertbozik@gmail.com/)).
The bindings have been reviewed and agreed; the driver review is
pending. The patches are in `upstream/`.

The libcamera side is not going upstream for now, so the nineteen
patches in `upstream/libcamera/` are carried here and applied at install
time. They are written to upstream standards anyway — clean commit
messages, every new tuning key off by default, no hacks specific to this
machine — so that they can be sent the day that changes.

## Licence

GPL-2.0, matching the kernel code, with per-file `SPDX-License-Identifier`
tags: the device tree binding is `GPL-2.0 OR BSD-2-Clause` as the kernel
requires, and the tuning file is `CC0-1.0`.

`vendor/ipu-bridge/ipu-bridge.c` is the kernel's own file with one line
added; its provenance is in `vendor/ipu-bridge/README.md`.

The colour matrices and the white point curve in `tuning/ov32c4.yaml`
were decoded from the tuning data that shipped with this camera module;
everything else in that file was measured on the camera itself. Each
block says which.

## Reporting problems

Open an issue. Useful things to include:

```sh
sudo bash install.sh --check
cat /sys/class/dmi/id/product_version /sys/class/dmi/id/product_name
uname -r
journalctl -k -b | grep -iE 'ov32c4|ipu|intel_ipu7'
```

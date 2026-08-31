# Lenovo Yoga Slim 9 14ILL10 (83CX) Linux drivers — OmniVision OV32C4 webcam, ALC287 speakers, Xe display

Three things do not work on this laptop under Linux out of the box: the
webcam does not exist at all, only the tweeters play, and the screen
blanks for a moment during video calls. This repository fixes all three.

Clone it, run one command, reboot.

```sh
git clone https://github.com/RobertBozik/lenovo-yoga-slim-9-14ill10-linux-drivers.git
cd lenovo-yoga-slim-9-14ill10-linux-drivers
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

The position is kept in millimetres from the panel edge, not in pixels,
so a different resolution or desktop scale does not invalidate the
calibration. It does invalidate what the running process believes: Qt
keeps the screen data it read at startup and reports the old geometry,
scale and DPI after the change. The service therefore watches
`~/.config/kwinoutputconfig.json` and re-executes itself when the
compositor rewrites it, which takes about a second; under a compositor
that does not write that file, restart the service by hand after changing
the display (`systemctl --user restart udc-mask`).

**Both speakers.** Out of the box pin `0x17` is connected to the wrong
source: the woofers stay silent and the volume control is not even in the
audible path. The kernel already has the right fixup but does not pick it
for this machine, because its quirk table has no entry for PCI SSID
`17aa:380b`. Until that entry is upstream
([bugzilla #221902](https://bugzilla.kernel.org/show_bug.cgi?id=221902))
the model is forced by hand.

Once they play, the balance may not be to your taste: the woofers run at
their full calibrated gain and nothing in the path splits the bands or
corrects the response, which is what the vendor DSP does under Windows.
The woofers are driven by the two Cirrus CS35L56 amplifiers and have their
own volume, separate from the tweeters, so the balance is a one-line
change. Measured on this machine: `400` is 0 dB, four steps make a
decibel, and muting these two controls while music plays removes the bass
and leaves everything else, which is how the assignment was confirmed.

```sh
amixer -c0 sset 'AMP1 Speaker' 386      # -3.5 dB
amixer -c0 sset 'AMP2 Speaker' 386
sudo alsactl store                      # survives a reboot
```

Both amplifiers have to be set; they are separate mono controls, one per
side. `alsamixer -c0` (F5 for all controls) does the same thing by ear.
The installer does not touch this - it is a matter of taste, and -3.5 dB
is only what one pair of ears preferred.

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

## Secure Boot

Everything here runs with Secure Boot enabled, so a dual-boot machine
does not need a trip into the firmware setup between operating systems.
Two things are in the way out of the box, and they are unrelated to each
other.

**The firmware does not accept the shim.** With Secure Boot on, this
machine refuses to load `\EFI\ubuntu\shimx64.efi` and falls through to
the next boot entry, so Linux appears to have vanished. The boot entry
and the binaries are fine: Canonical's shim is signed by *Microsoft
Corporation UEFI CA 2011*, and that certificate is not in this firmware's
`db`, which holds only the Windows and Lenovo certificates. Compare the
two yourself:

```sh
sudo efi-readvar -v db | grep CN=
sudo sbverify --list /boot/efi/EFI/ubuntu/shimx64.efi | grep CN=
```

The fix is one setting: **F2 → Security → Secure Boot → `Allow Microsoft
3rd Party UEFI CA` = Enabled**, which adds that certificate to `db`, then
`Secure Boot = Enabled`. The same menu offers `Reset to Setup Mode` and
`Restore Factory Keys` if you ever need to write `db` by hand.

**The modules need a key the firmware trusts.** DKMS already signs them
with the machine's own MOK — `modinfo -F signer ov32c4` shows it — but
that key has to be enrolled once:

```sh
sudo mokutil --import /var/lib/shim-signed/mok/MOK.der
```

It asks for a one-time password. Reboot, and MokManager comes up: *Enroll
MOK* → *Continue* → *Yes* → the password. `mokutil --list-enrolled`
should then show the machine's own key. Kernel updates need no repeat:
DKMS rebuilds and re-signs with the same key.

Two things are worth knowing. A running kernel ignores MOK keys entirely
while Secure Boot is off — `.machine` stays empty and there is no
`UEFI:MokListRT` line in the log — so testing this with
`module.sig_enforce=1` and Secure Boot off fails and proves nothing. And
with Secure Boot on the kernel is in lockdown, which disables hibernation;
suspend to RAM is unaffected.

## Known limitations

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
the sensor driver, and the one-line `ipu-bridge` entry — is at v3, posted
to linux-media on 2026-08-29
([lore](https://lore.kernel.org/linux-media/20260829115832.8749-1-robertbozik@gmail.com/)).
The bindings are acked; the driver has been through one round of review
and the review comments are addressed in v3. The patches are in
`upstream/`.

The driver here carries one block the upstream patches do not, fenced
with `NOT-UPSTREAM`: kernels up to 7.0 return `-EINVAL` instead of
`-EPROBE_DEFER` when the sensor probes before `ipu-bridge` has built the
fwnode graph, and the probe is then never retried — so on those kernels
the camera would not come up on roughly half the boots. Newer kernels
handle it themselves. `scripts/to-upstream.sh` removes the block when
copying the driver into a kernel tree.

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

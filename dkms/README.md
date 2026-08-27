# DKMS package for the OV32C4 camera

Until the series is in the kernel, `ov32c4.ko` and the patched
`ipu-bridge.ko` live out of tree. Copying them into `updates/` by hand
survives a reboot but not a kernel update; DKMS rebuilds them for every
new kernel instead.

```sh
sudo bash install.sh --step driver
sudo reboot
```

Both modules go to `/lib/modules/<kernel>/updates/dkms/`, which depmod
prefers over the distribution's own. The step removes older manual
copies from `updates/` that would shadow them, and checks with
`modinfo -n` that the module names really resolve into `updates/dkms`.
The modules are never swapped while running — `ipu-bridge` in particular
is only changed by a reboot.

After the reboot, `modinfo -n ov32c4` and `modinfo -n ipu_bridge` both
point into `updates/dkms/`, `media-ctl -d /dev/media0 -p | grep ov32c4`
finds the entity, and `wpctl status` lists the camera.

## The risk DKMS does not remove

`vendor/ipu-bridge/ipu-bridge.c` is a copy of the kernel's own file with
one line added. If a later kernel changes `include/media/ipu-bridge.h`
or that file, the build fails — and because both modules are one DKMS
package, `ov32c4` does not get installed either. The fix is to take the
new `ipu-bridge.c` from that kernel's source, add the line back (see
`vendor/ipu-bridge/README.md`), and run the step again. The permanent
fix is the series being merged; see `upstream/`.

## Device node permissions

`/dev/video*`, `/dev/v4l-subdev*` and `/dev/udmabuf` get their ACLs from
logind only once the seat's session is **active**. WirePlumber starts
earlier, and libcamera does not retry a device after `Permission denied`,
so the camera is missing from PipeWire until the service is restarted.
The deterministic fix, which the `loopback` step applies:

```sh
sudo usermod -aG video,kvm "$USER"    # kvm owns /dev/udmabuf on Ubuntu
```

and a fresh login. To check: after a reboot, without restarting anything
by hand, `wpctl status | grep -i camera` finds the camera and
`journalctl --user -u wireplumber -b | grep -c 'Permission denied'` is 0.

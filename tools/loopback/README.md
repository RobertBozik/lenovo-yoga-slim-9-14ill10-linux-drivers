# `/dev/video42` — the camera for every application

The goal is a camera that behaves the way it does under Windows: every
program finds it, with nothing to configure. Programs that speak plain
V4L2 — Viber, Zoom, Cheese, browsers without flags — cannot see a
libcamera-only camera at all, and two simultaneous PipeWire clients of
libcamera crash today (Chromium up to 151: a division by zero, because
the `Format` from the PipeWire libcamera plugin carries no frame rate;
WirePlumber 0.5: a bug in `find-best-target.lua`).

So:

* a `v4l2loopback` node `/dev/video42` named "Lenovo OV32C4", with
  `exclusive_caps=1` — Chromium drops a device that also reports
  `VIDEO_OUTPUT`. The format, YUYV 1280x720 at 15 fps, is fixed by the
  udev rule (`set-caps`, `keep_format`) so the capture side is valid even
  with no feeder running.
* `ov32c4-camera-watch`, a user service, keeps the node open
  **permanently**: in v4l2loopback 0.15 the capture side is only alive
  while a writer is streaming, and `ENUM_FMT`/`G_PARM` return `EINVAL`
  otherwise — which applications report as "not negotiated". While idle
  it writes a black frame twice a second with the sensor off; when a
  program opens the node it starts `libcamerasrc → fdsink` and feeds real
  frames; twelve seconds after the last reader leaves, it stops again.
* a WirePlumber rule hides the loopback from PipeWire applications, so
  the camera is not offered to them twice.

Installed by:

```sh
sudo bash install.sh --step loopback
```

## Limitations

Measured, not assumed:

* **One owner at a time.** If a PipeWire client is holding the camera
  through libcamera, the feeder cannot start and the loopback stays
  black — and the other way round.
* **The watcher only sees readers belonging to the same user**, because
  it finds them through `/proc`.
* The proper fix for two simultaneous clients is upstream: a frame rate
  in the PipeWire plugin's `Format`, and the WebRTC fix that browsers
  pick up after M151.

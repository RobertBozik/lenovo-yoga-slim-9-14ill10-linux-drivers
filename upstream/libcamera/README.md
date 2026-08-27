# libcamera patches

Nineteen patches against libcamera, applied by the `libcamera` step of
the installer. The tree is pinned to the commit they were made against:

```
35c137c2f3e7104b96702c649344fafc91d8e233
libcamera: pipeline: simple: Delay stream count for software ISP
```

(libcamera 0.7.2 plus a few commits, 2026-08-24.) `LIBCAMERA_REF`
overrides the pin, `LIBCAMERA_SRC` moves the source tree.

The first seven were posted to libcamera-devel on 2026-08-26. The rest
have not been submitted. Either way they are written to upstream
standards — clean commit messages, checkstyle clean, every new tuning
key off unless the tuning file turns it on, nothing specific to one
machine — so the series can go out unchanged if that becomes possible.

What they add, in order:

```
0001  sensor properties for the OV32C4
0002  sensor helper (gain code <-> gain) for the OV32C4
0003  FrameDurationLimits through vertical blanking
0004  pass the startup controls to the software ISP
0005  converge faster, and digital gain in the ISP
0006  let the tuning file bound the default frame duration
0007  temporal noise reduction
0008  lens shading correction (GPU and CPU paths)
0009  highlight protection in the AGC, with hysteresis
0010  a linear toe at black in the gamma curve
0011  subtract the veil of scattered light
0012  one luminance histogram with finer bins
0013  let the tuning file set the default saturation
0014  start bright, settle before judging, damp the jumps
0015  zone statistics and centre-weighted metering
0016  weight the AWB statistics by zone
0017  meter the median instead of the mean
0018  meter a tunable percentile
0019  meter the skin when there is some
```

Patches 0008 onwards exist because the sensor sits under an OLED panel
and because the software ISP has to do everything an ISP chip would
normally do. Each is off by default; the tuning file in `tuning/` turns
on what this camera needs.

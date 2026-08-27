# The kernel series

Three patches, posted to linux-media on 2026-08-26:

```
0001  dt-bindings: media: i2c: Add OmniVision OV32C4
0002  media: i2c: Add driver for OmniVision OV32C4    (+ Kconfig, Makefile, MAINTAINERS)
0003  media: ipu-bridge: Add OmniVision OV32C4
```

<https://lore.kernel.org/linux-media/20260826072002.14357-1-robertbozik@gmail.com/>

Status: the bindings have been reviewed and agreed; the driver review is
pending, and a v2 is prepared.

Patch 0003 is one line. Without the
`IPU_SENSOR_CONFIG("OVTI32C4", 1, 400000000)` entry the bridge never
builds the fwnode graph, the sensor's probe is deferred for ever and the
camera never binds. The link frequency, 400 MHz (800 Mbps per lane), was
read out of the vendor driver's mode descriptors and confirmed on the
machine.

These patches are here for reference and for anyone who wants to build a
kernel with the driver in tree. The installer does not use them — it
builds the same driver out of tree with DKMS, from `src/ov32c4.c`.

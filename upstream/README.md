# The kernel series

Three patches, currently at v2 on linux-media:

  0001  dt-bindings: media: i2c: Add OmniVision OV32C4
  0002  media: i2c: Add driver for OmniVision OV32C4
        (+ Kconfig, Makefile, MAINTAINERS)
  0003  media: ipu-bridge: Add OmniVision OV32C4

- v1, 2026-08-26:
  <https://lore.kernel.org/linux-media/20260826072002.14357-1-robertbozik@gmail.com/>
- v2, 2026-08-28:
  <https://lore.kernel.org/linux-media/20260828132104.21473-1-robertbozik@gmail.com/>

The bindings have been reviewed and agreed; the driver review is
pending. v2 carries the binding review comments, two fixes in the driver
(pm_ptr() rather than pm_sleep_ptr(), and the control handler freed
correctly on the probe error path) and a trailer ordering fix.

Patch 0003 is one line. Without the
IPU_SENSOR_CONFIG("OVTI32C4", 1, 400000000) entry the bridge never
builds the fwnode graph, the sensor's probe is deferred for ever and the
camera never binds. The link frequency, 400 MHz (800 Mbps per lane), was
read out of the vendor driver's mode descriptors and confirmed on the
machine.

These patches are here for reference and for anyone who wants to build a
kernel with the driver in tree. The installer does not use them - it
builds the same driver out of tree with DKMS, from src/ov32c4.c.

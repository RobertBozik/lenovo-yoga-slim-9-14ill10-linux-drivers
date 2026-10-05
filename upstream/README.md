# The kernel series

Three patches, currently at v4 on linux-media:

  0001  dt-bindings: media: i2c: Add OmniVision OV32C4
  0002  media: i2c: Add driver for OmniVision OV32C4
        (+ Kconfig, Makefile, MAINTAINERS)
  0003  media: ipu-bridge: Add OmniVision OV32C4

- v1, 2026-08-26:
  <https://lore.kernel.org/linux-media/20260826072002.14357-1-robertbozik@gmail.com/>
- v2, 2026-08-28:
  <https://lore.kernel.org/linux-media/20260828132104.21473-1-robertbozik@gmail.com/>
- v3, 2026-08-29:
  <https://lore.kernel.org/linux-media/20260829115832.8749-1-robertbozik@gmail.com/>
- v4, 2026-10-05:
  <https://lore.kernel.org/linux-media/20261005071010.7191-1-robertbozik@gmail.com/>

The bindings are acked and unchanged since v2. The driver has been
through one full round of review (v3 addressed it) and v4 settles the
one question that was still open: the sensor's second I2C address.

The module answers on two addresses, 0x36 (the sensor) and 0x3e, and the
sensor does not respond until a register at 0x3e has been written. v1–v3
reached 0x3e with a bare `i2c_transfer()` and asked the reviewers how
they would like it done. v4 answers with a measurement instead: polled
across a power cycle, the block at 0x3e NACKs while the sensor is off,
appears about a millisecond after reset is released, and disappears with the sensor's
supplies — it is part of the sensor module, so the sensor driver owns it.
The driver now claims the address with `devm_i2c_new_dummy_device()`,
talks to it through a second CCI regmap, and treats a failed write there
as a power-on failure rather than carrying on. v4 also moves the software
reset out of the mode table into `enable_streams()` (the 10 ms delay in
the table was a busy-wait, because the CCI regmap cannot sleep), tightens
the power-on timing to what was measured (reset held 5 ms, 1 ms after
release), and fixes three findings from the automated review of v3.

Patch 0003 is no longer one line. Besides the
`IPU_SENSOR_CONFIG("OVTI32C4", 1, 400000000)` entry — without which the
bridge never builds the fwnode graph, the sensor's probe is deferred for
ever and the camera never binds — it tells the bridge not to instantiate
a `dw9714` focus driver for this sensor. The firmware's SSDB claims one
(`vcmtype = 2`), but the device at that address is the block described
above, not a VCM, and a `dw9714` there would fight the sensor driver for
it. The link frequency, 400 MHz (800 Mbps per lane), was read out of the
vendor driver's mode descriptors and confirmed on the machine.

These patches are here for reference and for anyone who wants to build a
kernel with the driver in tree. The installer does not use them - it
builds the same driver out of tree with DKMS, from `src/ov32c4.c` and
`vendor/ipu-bridge/ipu-bridge.c`.

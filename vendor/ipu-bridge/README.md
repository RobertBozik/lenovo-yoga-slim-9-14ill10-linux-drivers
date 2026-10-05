# ipu-bridge.c (patched copy)

`ipu-bridge.c` here is the kernel's own
`drivers/media/pci/intel/ipu-bridge.c` (SPDX GPL-2.0, author Dan Scally)
taken from Ubuntu kernel **7.0.0-30-generic**, with two changes:

1. an entry in the sensor table:

   ```c
   IPU_SENSOR_CONFIG("OVTI32C4", 1, 400000000),
   ```

2. an exception list `ipu_no_vcm_hids[]` containing `OVTI32C4`, checked in
   `ipu_bridge_parse_ssdb()`: the firmware's SSDB claims a VCM
   (`vcmtype = 2`) at the sensor's second I2C address, but the device there
   is part of the sensor module and is driven by `ov32c4` itself, so the
   bridge must not instantiate a `dw9714` on it.

The link frequency (400 MHz = 800 Mbps per lane) was read out of
the vendor driver's mode descriptors and confirmed on the machine.
The upstream submission of the same change is
`upstream/v4-0003-media-ipu-bridge-Add-OmniVision-OV32C4.patch`; once it
is merged, this copy becomes unnecessary.

**Why a full copy and not just the patch:** the driver has to be built
out of tree, and the kernel does not ship this .c file in the headers
package, so the patch alone would need the full kernel source (~200 MB)
on every machine.

**Risk:** this is a snapshot. If a later kernel changes
`include/media/ipu-bridge.h` or the file itself, the build may fail or
this copy may lag behind upstream fixes. The installer checks the
running kernel version and warns. To refresh: take the new
`ipu-bridge.c` from that kernel's source, add both changes above, replace
this file.

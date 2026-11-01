# Sound modes for the internal speakers

Under Windows the speakers run through the vendor's audio processing with
three modes - Music, Movie and Game - cycled by the key with the speaker
and the gear on it. The processing itself is closed, but the speaker
tuning it applies for this machine is plain data shipped with the Windows
audio driver. These three PipeWire filter chains rebuild the parts of it
that are ordinary signal processing:

- the speaker correction: a 20-band curve per profile, turned into one
  FIR filter per channel (`*.irs`, run by PipeWire's built-in convolver),
- the speaker filters: a 4th-order high-pass at 80 Hz, a -3 dB dip at
  400 Hz and a shelf at 3.3 kHz,
- the per-band compressor and the speaker regulator (LSP multiband
  compressor), and a limiter at the end.

Movie also has the two stages its profile switches on that the converter
can rebuild: the dialog enhancer (about +1.9 dB around 2.5 kHz, amount 5
of 16) and the volume leveler (LSP autogain). What is not rebuilt: the
surround virtualizer (Movie and Game), the leveler's own compressor and
the content-driven steering of the Dynamic profile. Game therefore stays
close to Movie without its dialog and leveler stages; Music uses none of
those anyway.

Each mode is a WirePlumber smart filter in front of the speaker sink
(`filter.smart`, WirePlumber 0.5): the speakers stay the default output
and WirePlumber routes whatever plays on them through the filter that is
enabled. Music is enabled by default, Movie and Game are not; the sound
mode key enables the next one through WirePlumber's `filters` metadata
(`filter.smart.disabled`) and the hotkeys service remembers it. After
Game comes Neutral, which disables all three: the speakers unprocessed. The
volume stays on the speakers, so the volume keys work as without the
modes; the filters stay at 100 %. Plasma lists them as virtual devices,
named "Speakers: Music" and so on in the session's language (Slovak,
Czech, German, else English).

Needs the LSP plugins as LV2 (`lsp-plugins-lv2`) and PipeWire's LV2
support, which Ubuntu ships separately in `libspa-0.2-modules-extra`.

## Where the numbers come from

- Tuning file: `DEV_0287_SUBSYS_17AA3905_PCI_SUBSYS_380B17AA.xml` from the
  Windows driver package `dax3_ext_rtk.inf` (tuning version 27, dated
  2025-01-20). `DEV_0287` is the ALC287 codec, `17AA3905` its subsystem ID,
  `380B` the PCI subsystem ID of the audio controller - this machine.
- Converted with
  [speaker-tuning-to-easyeffects](https://github.com/antoinecellerier/speaker-tuning-to-easyeffects)
  (MIT), commit `61f2d4a`, `dolby_to_pipewire.py --profile <mode>
  --target-sink ''`, balanced variant; for `movie` also `--enable dialog
  --enable autogain`, the two stages that profile has on.
- One change before converting: the file switches the tonal voicing off
  (`ieq-enable` 0) in every profile, but the converter then applies its own
  default voicing at 10 %. To match what the machine does under Windows,
  the conversion ran on a copy with `ieq-enable` 1 and `ieq-amount` 0 - no
  voicing. The difference is up to 2.8 dB around 240 Hz in Music and
  under 2 dB in the other two; by ear the version without it sounded best.
- Afterwards only names and paths were changed: the sink names, the
  description, the `.irs` location under `/usr/local/share/yoga-soundmodes/`,
  and the smart filter properties (name, the speaker sink as target,
  disabled for Movie and Game).

To regenerate, apply the same change to the XML and run the converter for
`music`, `movie` and `game`, then redo the renames above.

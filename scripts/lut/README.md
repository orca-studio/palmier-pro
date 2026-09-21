# Local VF LUT validation

Convert a user-supplied local `VF_V` cubic RGB float32 volume into the existing
Palmier `color.lut` interface. No cache files are bundled or downloaded.

```sh
python3 scripts/lut/convert_vf.py /absolute/path/filter.cube.vf /absolute/path/look.cube
python3 -m unittest discover -s scripts/lut -v
PALMIER_TEST_LUT=/absolute/path/look.cube swift test --filter LocalLUTIntegrationTests
```

The integration test is for the captured 16³ black-and-white look. Set
`PALMIER_TEST_LUT_FRAME` to an optional PNG to render a frame through Palmier's
actual effect registry and Metal kernel. Outputs are written next to the LUT.
Without `PALMIER_TEST_LUT` the local-resource integration test is skipped.

In Palmier, select a video clip, open Adjust → LUTs, choose the generated `.cube`,
and vary intensity from 0 to 100%. Confirm the original at zero and black-and-white
at full strength. Save/reopen and export a short clip to verify the UI lifecycle.

The converter validates magic, dimensions, exact payload length, finite normalized
values, and refuses to overwrite an existing output. Nine significant decimal
digits preserve float32 samples. The inferred storage order is x-fastest RGB.
Palmier uses tetrahedral interpolation; Jianying uses a normalized 3D texture
sampler. Sampling coordinates, interpolation and color management have not been
matched pixel-for-pixel. This is a resource-usability test, not visual parity.

## Effect package sample

```sh
python3 scripts/lut/package_jianying.py /absolute/path/7429744855724641545 /absolute/path/hd-monochrome.palmierfx
PALMIER_TEST_LUT=/absolute/path/hd-monochrome.palmierfx swift test --filter 'EffectPackageTests|LocalLUTIntegrationTests'
```

The adapter accepts the reviewed LUT fingerprint only and requires an unambiguous
revision directory. It inventories original files but does not execute or bundle
native scripts. The generated folder contains `manifest.json` and `look.cube`.
The v1 manifest identifies the package, display name, renderer (`color.lut`) and
resource hash. Unknown renderers, path traversal and modified resources fail.
Parameter defaults and intensity bounds remain owned by Palmier's EffectRegistry.

Select the generated `.palmierfx` folder in Adjust → LUTs. Import validates the
manifest/hash, then stores a normal local LUT for the existing undo/persistence/
render pipeline. This version flattens the package to a LUT when importing; it
does not retain package identity in clip state, execute general effect graphs,
or introduce remote download, particles, segmentation or native Lua support.

Manual check: select a clip and import the folder; check full/zero intensity,
undo, save/reopen and short export. Modify look.cube and import again: expect
an explicit error and no timeline change. If the timeline changes during import,
expect refusal instead of applying to stale state.

## Captured Star II sequence experiment

`EffectPackage.sequenceURL` validates `overlay.sequence` packages carrying
`overlay.mov` plus sequence dimensions, frame count, frame rate and blend mode.
`SequenceEffect.clip` maps native speed control with `0.5 + 1.5 * control`, applies
screen blending/intensity, and rejects non-finite controls or durations beyond a
single captured cycle. It reuses Palmier's existing video compositor and export.
This renderer is a sprite-sequence adapter, not a realtime particle simulator.
The current LUT picker remains LUT-only; sequence package UI import is not wired.

Local acceptance:

```sh
PALMIER_TEST_SEQUENCE=/absolute/path/star-ii.palmierfx swift test --filter 'SequenceEffectTests|LocalSequenceIntegrationTests|EffectPackageTests'
```

Star II's 151 PNGs are encoded as ProRes 4444 at 25fps for AVFoundation. The
QuickTime Animation codec failed on this machine and is not used. ProRes is not
a lossless RGB roundtrip. Portrait rotation, repeat-cycle semantics and native
color/timing parity remain unverified.

Rebuild the reviewed star package with:

```sh
python3 scripts/lut/package_star_ii.py /absolute/path/to/250f8b0955f88b6d3df995612739f2b3 /absolute/path/star-ii.palmierfx
```

## Editable flower text experiment

`EffectPackage.textStyle` validates a `text.decoration` manifest and hashed
`style.json`. Its fill and up to eight ordered outlines are applied to editable
text through Text → Import…, using the existing undo/persistence path. Outlines
are rendered by Core Text in both normal and per-word animation paths.

The local yellow/orange sample maps native SDF thresholds to glyph-relative
outline widths experimentally. It uses the selected Palmier font: the package's
referenced font is absent. This is not a native SDF/Lua runtime or a claim of
pixel parity. Gradient/texture text fills are not implemented.

Manual acceptance remains required: import the local flower package, edit the
text, undo/redo, save/reopen and export. The automated checks cover outline
colors and model roundtrip; they do not replace this UI lifecycle check.


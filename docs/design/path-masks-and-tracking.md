# Path masks and subject tracking

A clip can be limited to the inside of a closed path, that path can be keyframed, and
Vision can author those keyframes automatically. This document covers the data model,
the invariant everything rests on, the render pipeline, and the tracking contract.

For conceptual background — where `mask` sits among `crop`, `transform`, `opacity` and
`blend`, and why those belong to one family — see the glossary note
[合成属性族](https://orcastudio.feishu.cn/wiki/DWUWwHWn7imDHSkhk4Pc8kWfneh).
This document stays on the implementation.

## Why

Every effect in `EffectRegistry` is full-frame. Grades, blurs, keys and stylize passes
all apply to the whole clip, so nothing could be confined to a region — no masked
reveals, no local grading, no cut-out graphics, no text passing behind an object. A
path mask is the missing primitive.

It also removes the need for a separate shape-layer concept: a solid-colour matte
(`import_media` with `source.matte`) supplies the fill, the mask supplies the shape.

## Data model

`Sources/PalmierPro/Models/Timeline.swift`

```swift
struct MaskVertex { var point: AnimPair; var inControl: AnimPair?; var outControl: AnimPair? }
struct MaskShape  { var vertices: [MaskVertex]; var feather: Double; var inverted: Bool }

// on Clip, mirroring the existing crop / cropTrack pair
var mask: MaskShape?
var maskTrack: KeyframeTrack<MaskShape>?
```

Coordinates are **0–1 of the source's display box** — the same space as `Crop`, not the
canvas. The mask therefore rides with the content: move, scale or rotate the clip and
the path follows, because it is applied before placement.

Decoding is additive and every field optional, so projects written before this feature
load unchanged. Corrupt values are dropped on decode by `MaskShape.sanitized` rather
than reaching the rasterizer.

### The invariant

> **Vertex count belongs to the track, not to a keyframe.**

Interpolation pairs anchors by index, and there is no honest way to invent a pairing
between paths of different length. Adding or removing a point therefore rewrites *every*
keyframe on the track, and `keyframeInterpolate` holds the earlier shape rather than
guess if it ever meets a mismatch.

Enforced in three places, so no caller can route around it:

| Where | What it does |
| --- | --- |
| `MaskShape.keyframeInterpolate` | Returns the earlier shape unchanged on a count mismatch |
| `set_keyframes` row validation | Rejects a `maskPath` payload whose rows disagree on count |
| `set_mask` / `insertMaskVertex` / `removeMaskVertex` | Refuse or propagate across all keyframes |

Ignoring this produces the worst kind of bug: a path that flails between keyframes for
reasons invisible in any single frame.

## Rendering

`Sources/PalmierPro/Compositing/PathMaskRasterizer.swift`, inserted into
`FrameRenderer.applyClipPipeline`:

```
crop → effects → path mask → corner mask → transform → opacity
```

*After effects* so a grade or blur covers the whole source and the mask cuts the
result — "open a window on the graded image" is what people expect. *Before placement*
so the path travels with the content.

Not a `CIKernel` like `EdgeRoundingKernel`: a rounded rectangle has a closed-form
distance field, an arbitrary bezier does not, and a kernel would have to walk every
segment for every pixel. The path is filled once with Core Graphics and applied through
`CIBlendWithMask`; feather is a Gaussian blur on the mask, sized as a fraction of the
source's shorter side so it looks the same at any resolution.

Masks are cached by a key covering the shape and the extent. A static mask rasterizes
once; an animated one changes the key every frame and pays one path fill per frame.

## Agent surface

| Tool | Purpose |
| --- | --- |
| `set_mask` | Static path, feather, inversion, clearing |
| `set_keyframes` property `maskPath` | Animate the path |
| `track_subject` | Author the keyframes from footage |

`maskPath` rows are `[frame, [[x, y], …], interp?]`. The vertex list is **nested, not
flattened**, so a row's arity cannot silently encode the point count — a flattened form
would turn "I dropped a vertex" into a valid-looking row of a different length.

## Subject tracking

`Sources/PalmierPro/Tracking/` + `EditorViewModel+Tracking.swift`

Two modes, chosen because they fail differently.

### `hands` — detection

`VNDetectHumanHandPoseRequest` runs independently on every frame and returns 21 named
landmarks per hand with per-point confidence. The quad is built from both hands'
`.thumbTip` and `.indexTip` — the corners a framing gesture actually makes.

No history means no drift. Measured on a 61-frame handheld clip: **61/61 frames
detected, lowest confidence 0.71, ~10 s total**.

Left and right are decided by **where each hand sits in frame**, not by Vision's
`chirality`: a mirrored front camera reports the anatomical hand, which is the opposite
of what the editor sees.

### `region` — tracking

`VNTrackObjectRequest` follows one box forward from a seed and moves the clip's existing
mask rigidly. It is the only option for subjects Vision has no detector for, and its
error accumulates. Measured against the hand landmarks on the same clip:

| Frames elapsed | Max error (fraction of frame width) |
| --- | --- |
| 10 | 0.02 |
| 30 | 0.15 |
| 60 | **0.22** |

Confidence tracked the failure closely — the two points that drifted fell to 0.07 and
0.01 while the two that held stayed at 0.65–0.80. That correlation is what makes the
mode usable at all: **track short spans and re-anchor**.

### The contract

> Tracking stops at the first frame whose confidence falls below `minConfidence`, and
> frames past it are left untracked.

Nothing is extrapolated. A mask that quietly slides off its subject is worse than one
that stops, because the first is only discovered by scrubbing the whole clip. The result
reports `lostAtFrame` so the caller can correct the mask there and re-run from that
frame.

### Phases

The gesture this was built for marks its own edits: the hands come together, then open
on a new shape. That reads in the data as the distance between the two index tips
collapsing — a deliberate, full-amplitude move, 0.004 to 0.548 on a test clip, two
orders of magnitude. `PhaseDetector` reports each approach as a boundary.

Two things share one threshold, on purpose: the span below which the hands count as
touching is both where a phase begins and where the mask stops drawing. They cannot
disagree about where a phase starts.

- **Below it**, the four corners sit on top of each other and any quad through them is
  noise — a visible spike. The path collapses to its centre instead: zero area draws
  nothing, the vertex count is untouched, and neighbouring frames interpolate into it,
  so the shape closes and reopens with the hands at no extra cost.
- **Above it**, the shape draws normally.

`phaseShapes` gives each phase its own vertex ORDER, cycled — four indices over the
tracked corners. Because a phase is an ordering rather than coordinates, the shape keeps
following the hands and the vertex count cannot change between phases.

The corners are first sorted clockwise about their centre. Without that they arrive in a
semantic order — left thumb, right index, right thumb, left index — which says nothing
about screen position, so as the hands turned the *same* order flipped between a simple
quad and a crossed one on its own, and phases were not actually distinct. Measured on a
real clip before the fix: frames 20 and 40 crossed, 60 did not, 90 did not, 110 and 130
did — inside what were meant to be two stable phases.

| Order | Shape |
| --- | --- |
| `[0,1,2,3]` | Quad |
| `[0,1,3,2]`, `[0,2,1,3]` | Bowtie — two triangles |
| `[0,1,2,2]` | Triangle: an index may repeat, collapsing a corner, so the apparent number of sides can change while the track keeps its four vertices |

### Cross-clip tracking

`sourceClipId` names the clip that is *analysed*; `clipId` names the clip that *receives*
the mask. They are usually different — masking an upper clip to the shape two hands make
in the footage below is the common case, and that is the difference between "a yellow
shape between my hands" and "a window into another video".

Only frames both clips cover are tracked (`TrackingPlan`), and source frames are computed
through the **subject's** own trim and speed.

## UI

- **Canvas** — pen tool in `Preview/MaskOverlayView.swift`. Click to place points, click
  the first point to close, drag anchors, right-click to add or delete one. Handles map
  through the clip's transform and crop, rotate with it, and mirror with its flips.
- **Auto-keyframe** — dragging an anchor while a track is live upserts a keyframe at the
  playhead instead of flattening the animation, the same rule `crop` already follows.
- **Inspector** — Mask row with feather / invert / clear, plus `Track Hands` and
  `Track This Mask`. The row itself reports the outcome (`61 kf tracked`,
  `lost at f34 · 20 kf`), so a track that stopped early is visible where it was started.
- **Keyframe editor** — a Mask lane alongside position, scale, rotation, opacity, crop.

## Interchange

| Path | Behaviour |
| --- | --- |
| Video export | Rendered |
| `.palmier` project | Preserved |
| XMEML (`xml`) | Omitted — the format has no mask concept |
| FCPXML | Omitted — its shape masks have different semantics, and a lossy mapping would be worse than none |

This matches how `edgeRounding` and `edgeSoftness` are already handled.

## Not built

- Bezier handles and feather are in the model and honoured by the rasterizer, but have
  no UI; only the Agent can set them.
- One mask per clip. `MaskShape` is a single value, not an array — boolean combinations
  of several masks would need a list and a compositing rule.
- Effect-level masks. The mask limits the whole clip, not one effect in its stack.
- Body and face landmarks. `VNDetectHumanBodyPoseRequest` (19 points) and
  `VNDetectFaceLandmarksRequest` (76 points) are the obvious next detectors; the tracking
  seam takes them without structural change.

## Verification

- 62 automated tests: rasterization (inside/outside, inversion, y orientation, degenerate
  paths, feathered edges), interpolation (index pairing, the count-mismatch hold, track
  sampling, split/rebase, sanitisation), vertex editing (track-wide insert/delete,
  auto-keyframing, the three-point floor), and tracking (frame mapping through trim and
  speed, overlap clamping, the confidence stop, rigid region moves, phase detection and
  its de-bounce, the closed-hand collapse, and the canonical corner order).
- End-to-end through MCP on handheld footage: `track_subject` wrote 61 keyframes in one
  call and the export matched the hands frame by frame.
- **UI is not covered by tests** and needs a person at the keyboard: pen drawing, anchor
  dragging, the context menu, auto-keyframing, Escape/Return, multi-selection disabling,
  and mutual exclusion with crop editing.

### What the tests are for, and what they are not

Worth stating plainly: **no defect in this feature was found by a test.** Every one —
fingertips assigned to the wrong finger, a reflection landing on top of what it
reflected, the spike at a pinch, phases that were not actually distinct — was found by
rendering frames and looking at them.

That is not an argument for fewer tests. It is an argument about what they cover here.
The ones that earn their place assert things invisible in any single frame: interpolation
holding on a vertex-count mismatch (whose symptom is an occasional flail while
scrubbing), tracking stopping instead of extrapolating (a mask that slides off over
seconds), frame mapping through the subject's own trim and speed (an offset that looks
"about right"). They pin decisions down for the next change; they do not discover
whether a shape looks good.

The gap is a middle layer that does not exist yet: golden frames, plus the measurements
that actually caught things during development — sampling colour at a cut frame, mask
area per frame, self-intersection tests, drift against hand landmarks as ground truth.
Those were written as throwaway scripts. Nothing currently stops a change to the pipeline
order, the canonical ordering or the collapse threshold from quietly altering footage
already signed off.

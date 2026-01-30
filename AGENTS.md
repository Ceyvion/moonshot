# agents.md

This repo builds an iOS app that enhances moon photos without AI-looking artifacts. The product promise is evidence-based enhancement: we amplify captured signal, we do not invent crater texture or replace regions with synthetic detail.

This file defines the agent roles, operating constraints, deliverables, and handoff contracts for building the app.

## Non-negotiables

1. No generative fill, no texture synthesis, no patch replacement, no "swap-in" moon assets.
2. Detail enhancement is gated by measured confidence in the input signal.
3. Limb integrity is sacred. Prevent halos and ringing at the moon edge.
4. Sky stays dark and boring by default. Avoid lifting noise into gray.
5. If input lacks detail or highlights are clipped, output stays natural and conservative.
6. All processing is on-device unless explicitly designed otherwise.

## Product goals

- One-tap results that look like a better version of the same capture.
- A capture mode (video or burst) that produces real improvements via stacking.
- Two strength presets (Natural, Crisp) that share the same honesty constraints.
- Clear user feedback that sets expectations without tutorials.

## User pain points (what we are solving)

- Users capture a blown-out white disk with no detail.
- Auto exposure and HDR clip highlights or introduce halos.
- Hand shake and atmospheric turbulence blur detail that users mistake for focus failure.
- Editing apps over-sharpen, add micro-contrast, and create repeating textures that read as fake.
- Users want one tap, then they want control, and they want to trust the output.

## High-level architecture

Modules:
- Capture: AVFoundation camera pipeline, exposure/focus locking, optional burst/video capture.
- Detection: moon detection, circle fit, crop extraction, mask generation, confidence scoring.
- Reconstruction: frame extraction, sharpness scoring, alignment, stacking, optional drizzle 2x.
- Enhancement: tone, denoise, deconvolution, wavelet sharpening, halo control, chroma cleanup.
- UX: presets, single strength slider, before/after, Reality Meter, export/share.
- Telemetry (optional, privacy-first): on-device metrics only, no image upload by default.

Processing is deterministic. Every output can be reproduced from the same input and parameters.

## Agent roster

### 1) Product Agent
Purpose: turn the concept into shippable scope with crisp acceptance criteria.

Responsibilities:
- Define MVP scope and post-MVP backlog.
- Specify UX flows and copy for trust-building.
- Maintain "Non-negotiables" compliance and veto risky features.

Deliverables:
- MVP definition and timeline broken into milestones.
- Feature flags list for risky or expensive components.
- User stories and acceptance tests at the UX level.

Acceptance criteria:
- A first-time user can produce a noticeably improved moon crop in under 30 seconds.
- The app never outputs obvious limb halos in default settings.
- The app communicates capture quality clearly (Low/Medium/High).

### 2) Vision Algorithms Agent
Purpose: implement evidence-based enhancement.

Responsibilities:
- Moon detection and circle fit with confidence.
- Detail confidence map C in [0,1] used as a gate across sharpening-like steps.
- Halo detection and mitigation loops.
- Parameter sets for Natural and Crisp.

Deliverables:
- `MoonDetection.swift` with unit-tested geometry outputs: circle, crop rect, mask.
- `ConfidenceMap.swift` with deterministic outputs and test fixtures.
- `HaloGuard.swift` with overshoot metric and mitigation steps.
- Preset parameter tables and interpolation logic (slider).

Acceptance criteria:
- Detection succeeds on diverse devices and typical moon exposures.
- C map correlates with perceived detail and prevents sharpening in low-signal regions.
- Halo guard catches overshoot and reduces it below preset thresholds.

### 3) iOS Performance Agent
Purpose: make the pipeline fast, stable, battery-aware.

Responsibilities:
- Metal compute kernels for heavy operations (FFT, convolutions, phase correlation).
- Progressive rendering: preview first, final render second.
- Memory bounds and frame pipeline efficiency.

Deliverables:
- `Renderer.swift` with preview and final render pathways.
- Metal shaders for alignment and filtering where necessary.
- Benchmarks on representative devices.

Acceptance criteria:
- Preview render under 300 ms for a 512 px moon crop.
- Final render under 2 seconds for typical stills.
- Video stacking mode under 6 seconds for 1–3 seconds input on modern devices.

### 4) UX Agent
Purpose: build a UI that feels like an instrument, not a magic trick.

Responsibilities:
- Design the One-tap Enhance screen and the Capture for Detail screen.
- Before/after comparison UX that reduces skepticism.
- Reality Meter that sets expectations.
- "Authenticity Lock" that is visible and meaningful.

Deliverables:
- SwiftUI screens and states.
- Microcopy: capture prompts, clipped highlight warnings, quality labels.
- Empty-state and error-state UX for low-confidence detection.

Acceptance criteria:
- Users can understand why a result is conservative.
- Users can choose Natural vs Crisp and feel the difference without fakeness.
- Users can export/share without losing EXIF.

### 5) QA and Test Agent
Purpose: ensure correctness, reproducibility, and safety across edge cases.

Responsibilities:
- Golden image tests for representative scenarios.
- Regression tests for halos, clipping, and color fringing.
- Stress tests: long video, low battery mode, thermal throttling.

Deliverables:
- Test dataset guidelines and local fixtures (do not ship copyrighted assets).
- Snapshot tests for pipeline outputs and masks.
- Performance regression thresholds.

Acceptance criteria:
- No new release increases halo overshoot metrics on the golden set.
- No crash on malformed media inputs or interrupted capture.
- Output parameters are logged and reproducible.

### 6) Privacy and Security Agent
Purpose: guard user trust.

Responsibilities:
- Confirm all processing is on-device by default.
- Ensure photo library permissions are scoped and clear.
- Ensure any analytics are opt-in and image-free.

Deliverables:
- Privacy manifest and permission copy.
- Data flow documentation.
- Settings toggles for telemetry and export metadata.

Acceptance criteria:
- No network calls in the enhancement pipeline.
- No images or derived textures leave the device.
- Permissions requested only when needed.

## Processing contracts (handoffs)

### Detection output contract
Inputs:
- Still image or video frames
Outputs:
- `moonCircle`: center (x,y), radius r
- `cropRect`: padded rect around moon
- `moonMask`: soft mask M, feathered edge
- `limbRingMask`: inner band mask for edge protection
- `circleConfidence`: float 0..1
- `clippedHighlightFraction`: float 0..1 within moon mask

Failure behavior:
- If `circleConfidence < 0.5`, fall back to conservative global edits and require manual crop or show guidance.

### Confidence map contract
Inputs:
- Luminance crop and noise estimate
Outputs:
- `C`: confidence map 0..1
- `medianC`, `snrMap` (optional)

Rules:
- All sharpening-like operations must be multiplied by a monotonic function of C.
- Limb ring must reduce C smoothly to prevent edge artifacts.

### Halo guard contract
Inputs:
- Processed luminance and limb ring mask
Outputs:
- `overshootMetric`: float
- `pass/fail` relative to preset threshold
- `mitigationApplied`: list of parameter adjustments

Rule:
- If overshoot fails, apply mitigation once and re-render final sharpen stage. No repeated loops.

## Presets (initial parameter sketch)

These are starting points. Tune per device and image depth.

### Natural preset (still)
- Tone:
  - highlight shoulder start: 0.82 * wp
  - shoulder strength: 0.55
  - midtone contrast gain: +0.10 (pivot 0.55)
- Denoise:
  - luma base: 0.35, applied as 0.35 * (1 - C)^1.3
  - chroma: 0.55
- Deconvolution:
  - only if circleConfidence > 0.6 and median(C) > 0.35
  - RL iterations: 3, PSF sigma: 0.8 px
  - update multiplier: (0.6 + 0.4 * C)
- Wavelet gains (luma):
  - fine: 0.18, mid: 0.12, coarse: 0.05
  - multiplied by C^1.2
  - limb ring multiplier: 0.35
- Micro-contrast:
  - radius 18 px, strength 0.07
  - only where C > 0.45 and not in limb ring
- Halo threshold:
  - overshoot <= 1.5%

### Natural preset (video)
- Select top N frames by sharpness: N = 12
- Weighted stack: weights = sharpness^1.2
- Sigma-clipped mean optional (2.5 sigma)
- Denoise luma base drops to 0.18
- RL remains 3 or 4 if median(C) is high

### Crisp preset (still)
- Tone:
  - shoulder start: 0.78 * wp
  - shoulder strength: 0.65
  - midtone contrast gain: +0.16 (pivot 0.52)
- Denoise:
  - luma base: 0.45, applied as 0.45 * (1 - C)^1.1
  - chroma: 0.65
- Deconvolution:
  - circleConfidence > 0.7, median(C) > 0.40, clippedHighlightFraction < 0.003
  - RL iterations: 6, PSF sigma: 0.7 px
  - update multiplier: (0.5 + 0.5 * C)
  - limb ring multiplier: 0.25
- Wavelet gains (luma):
  - fine: 0.32, mid: 0.22, coarse: 0.09
  - multiplied by C^1.35
  - do not sharpen where local snr < 4.0
- Micro-contrast:
  - radius 22 px, strength 0.11
  - only where C > 0.55
  - never in outer 10 px of the disk
- Halo threshold:
  - overshoot <= 2.2%

### Crisp preset (video)
- Select top N frames: N = 20
- weights = sharpness^1.6
- Drizzle 2x only if subpixel coverage is adequate (shift variance > 0.15 px in x and y)
- Denoise luma base: 0.14
- RL iterations: 7 only when clipping is low and median(C) is high

## Guardrails and failure modes

### No clip, no lie
If clippedHighlightFraction is above the threshold:
- Reduce contrast gains by 20 to 30 percent
- Disable RL
- Reduce fine sharpening by 40 percent
- Show: "Highlights clipped. Kept the result natural."

### Edge honesty
Always apply limb ring protection and halo guard.
If overshoot fails:
- Reduce fine wavelet gain by 35 percent
- Reduce RL iterations by 2 or disable RL
- Expand limb ring width by 3 px
- Re-run final sharpening stage once

### Sky discipline
Do not lift sky shadows by default.
If user increases sky slider:
- apply stronger chroma denoise to sky only
- cap sky lift to preserve black background

## UX flows (MVP)

### One-tap Enhance
- Import photo or use in-app camera
- Auto detect moon, auto crop
- Preset toggle: Natural / Crisp
- Strength slider 0..100 (interpolates within guardrails)
- Before/after slider
- Reality Meter: Low / Medium / High
- Export and share

### Capture for Detail
- Prompt: "Video works best for real detail."
- Auto lock exposure and focus when moon detected
- Stability meter, 1 second "hold" cue
- Record 1 to 3 seconds
- Frame selection summary (optional)
- Same preset and strength controls
- Export and share

## Definition of done (release checklist)

Functional:
- Still enhancement pipeline working end-to-end.
- Video stacking mode working end-to-end.
- Natural and Crisp presets implemented and tuned for halo safety.

Quality:
- Golden set snapshot tests passing.
- No regression in halo overshoot metrics.
- Performance targets met on representative devices.

Trust:
- Authenticity Lock implemented (no generative operations anywhere).
- Clear warning for clipped highlights and low capture quality.
- On-device processing verified, no network dependency.

## Suggested folder structure

- `App/`
  - `UI/`
  - `Capture/`
  - `Processing/`
    - `Detection/`
    - `Reconstruction/`
    - `Enhancement/`
    - `Presets/`
  - `Metal/`
  - `Tests/`
- `Docs/`
  - `pipeline.md`
  - `privacy.md`
  - `benchmarks.md`

## Agent operating rules

- Agents do not add features that violate "Non-negotiables."
- Agents document parameter changes with the reason and test evidence.
- Agents keep processing deterministic and reproducible.
- Agents prefer reconstruction from multiple frames over single-frame "smart" detail.
- Agents treat "AI-looking" as a measurable artifact class: halos, ringing, texture repetition, over-clarity, chroma fringing.

## Open questions (to resolve early)

- Input support: RAW/ProRAW pipeline vs HEIC-only MVP.
- Drizzle 2x: MVP flag or post-MVP.
- Export formats: HEIC vs JPEG vs PNG.
- Device tuning strategy: per model profiles or dynamic heuristics from EXIF and noise estimate.

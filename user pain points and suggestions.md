People try to photograph the moon and run into the same set of traps:

1.  They did not actually capture detail.Phones often deliver a bright white disk with a hint of maria. Digital zoom and tiny sensor pixels leave you with low real spatial information. Any strong sharpening reads as invented texture.
    
2.  Auto exposure and HDR sabotage the moon.The camera sees a black sky and a bright moon, then tries to “help.” The moon clips, or HDR introduces weird halos and tone steps. The user cannot tell what happened, they only see “my phone can’t do it.”
    
3.  Motion and atmosphere look like “bad focus.”Even with “focus locked,” micro shake and atmospheric turbulence blur fine detail. Users interpret it as user error. They start dragging sliders, and the edit becomes crunchy.
    
4.  The edit looks fake fast.Most “AI-looking” moon edits come from three things: limb halos, overdone micro-contrast, and crater texture that appears everywhere equally (including places that should be smooth).
    
5.  Users want one tap, then they want control.One tap has to deliver a pleasing result. Control has to exist, since moon photos vary wildly by lens, exposure, and phone model.
    
6.  Trust is the whole product.If the app ever swaps in a “better moon,” it becomes a toy. If it is visibly conservative, people call it “weak.” The winning path is a result that feels stronger while still feeling earned.
    

That leads to two presets that are not two “looks.” They are two strength settings of the same philosophy: evidence-based enhancement. The Crisp preset should still refuse to create detail where the input has none.

Below is a concrete parameter sketch you can implement and then tune per device.

Core pipeline assumptions

A) You isolate a moon crop and create a moon mask.

*   Circle fit confidence in \[0,1\]
    
*   Moon mask M: soft edge, feather 2–4 px at output resolution
    
*   Limb protection ring: 6–12 px band inside the edge where sharpening is limited
    

B) You build a “detail confidence map” C in \[0,1\].This gates every operation that can look fake.A simple first version:

*   Compute local gradient magnitude G on luminance
    
*   Compute local structure coherence S (from structure tensor, 0..1)
    
*   Estimate noise σ from sky region or dark areas in the crop
    
*   Estimate local SNR as snr = (local\_std / (σ + ε))
    
*   C = clamp01( w1 \* S + w2 \* normalize(G) + w3 \* normalize(snr) )Starting weights: w1=0.45, w2=0.25, w3=0.30Then zero it near the limb with a smooth falloff in the limb ring.
    

C) You always process luminance more than chroma.Most “fake” artifacts are chroma ringing and edge fringing.

Preset 1: Natural Moon

Goal: looks like a cleaner, more legible version of the same capture. It accepts softness in low-confidence regions.

Recommended defaults (single photo)

1.  Linearization and white balance
    

*   Work in a quasi-linear space.
    
*   If input is RAW/ProRAW: true linear.
    
*   If input is HEIC/JPEG: approximate inverse gamma (power 2.2) on the moon crop only, then re-encode later.
    

1.  Tone and highlights (moon region)
    

*   Highlight rolloff (soft shoulder):
    
    *   Define white point wp as 99.5th percentile of moon luminance inside mask.
        
    *   Map luminance with a shoulder starting at 0.82\*wp.
        
    *   Shoulder strength: 0.55
        
*   Midtone contrast:
    
    *   Gentle S-curve, contrast gain: +0.10
        
    *   Pivot around 0.55 of normalized moon luminance
        
*   Keep sky mostly untouched. Sky lift causes fake-looking gray background.
    

1.  Chromatic aberration and fringing cleanup
    

*   On the moon edge, reduce chroma magnitude by 10–20% within a 3–6 px band.
    
*   Optional CA correction: radial shift of chroma channels by 0.2–0.4 px if your circle fit confidence is high.
    

1.  Denoise (luminance first)Natural should remove noise without erasing crater boundaries.
    

*   Edge-aware denoise guided by C:
    
    *   Base luma denoise strength: 0.35
        
    *   Apply denoise as: strength\_local = 0.35 \* (1 - C)^1.3
        
    *   Guided filter radius: 3 px
        
    *   Guided filter epsilon: 0.006 (tune per 8-bit vs 16-bit pipeline)
        
*   Chroma denoise:
    
    *   Strength: 0.55
        
    *   Radius: 4 px
        

1.  Deconvolution (very mild, gated)
    

*   Only if circle fit confidence > 0.6 and median(C) > 0.35
    
*   PSF model: small gaussian
    
    *   sigma: 0.8 px at processing resolution
        
*   Richardson–Lucy iterations: 3
    
*   RL damping: apply a soft clamp on high frequencies using C
    
    *   Multiply RL update by (0.6 + 0.4\*C)
        
*   Skip RL in low-confidence cases. Natural has permission to remain soft.
    

1.  Wavelet sharpening (low gain, masked)Three-band wavelet or Laplacian pyramid sharpening on luminance only:
    

*   Band gains:
    
    *   Fine (1–2 px features): 0.18
        
    *   Mid (3–6 px): 0.12
        
    *   Coarse (7–14 px): 0.05
        
*   Apply gains multiplied by C^1.2
    
*   Limb ring multiplier: 0.35 (strong halo prevention)
    

1.  Micro-contrast (the “AI-looking” danger zone)Natural uses very little.
    

*   Local contrast radius: 18 px
    
*   Strength: 0.07
    
*   Mask: apply only where C > 0.45 and not in limb ring
    

1.  Halo and ringing controlAfter sharpening, test for limb overshoot:
    

*   Sample radial profiles across the limb at 36 angles.
    
*   Overshoot metric: peak overshoot magnitude / (moon interior peak)
    
*   Natural threshold: 1.5%If overshoot > threshold:
    
*   Reduce wavelet gains by 25%
    
*   Reduce RL iterations to 2 (or disable RL)
    
*   Increase limb ring width by 2 px
    

1.  Output
    

*   Re-apply gamma for display
    
*   Export the crop at a sensible size:
    
    *   If input is low detail, exporting at 1024–2048 px across the moon avoids “big fake.”
        
    *   If you do multi-frame drizzle later, you can export larger.
        

Natural Moon (video or burst) defaults

This is where Natural can still look impressive while staying honest.

*   Extract frames from 1–3 seconds video: aim for 30–90 frames
    
*   Sharpness score: variance of Laplacian on the moon crop
    
*   Keep top N frames:
    
    *   N = 12 (natural)
        
*   Alignment:
    
    *   Translation via phase correlation on luminance
        
    *   Subpixel refinement allowed
        
*   Stack:
    
    *   Weighted mean with weights proportional to sharpness^1.2
        
    *   Optional sigma-clipping: clip pixels beyond 2.5σ per stack location
        
*   Then apply the same Natural pipeline with denoise strength reduced:
    
    *   Base luma denoise strength drops from 0.35 to 0.18
        
    *   RL iterations can stay at 3, sometimes 4 if median(C) is high
        

Preset 2: Crisp Moon

Goal: more legible crater edges and maria boundaries, still believable. Crisp does not mean “overprocessed.” Crisp means you exploit multi-frame support when available and use stronger sharpening only where evidence exists.

Crisp defaults (single photo)

1.  Tone and highlights
    

*   Slightly stronger midtone contrast:
    
    *   Contrast gain: +0.16
        
    *   Pivot: 0.52
        
*   Slightly stronger highlight shoulder:
    
    *   Shoulder start: 0.78\*wp
        
    *   Shoulder strength: 0.65This keeps the bright limb from turning into a glowing rim after sharpening.
        

1.  DenoiseCrisp needs a cleaner base since sharpening amplifies noise.
    

*   Base luma denoise strength: 0.45
    
*   strength\_local = 0.45 \* (1 - C)^1.1
    
*   Guided radius: 3 px
    
*   Epsilon: 0.008
    
*   Chroma denoise strength: 0.65
    

1.  Deconvolution (stronger, still limited)Conditions:
    

*   circle fit confidence > 0.7
    
*   median(C) > 0.40
    
*   clipped highlight fraction inside moon mask < 0.3% (if clipped, RL will ring and look fake)Parameters:
    
*   PSF sigma: 0.7 px
    
*   RL iterations: 6
    
*   Apply RL update multiplier: (0.5 + 0.5\*C)
    
*   Limb ring multiplier: 0.25
    

1.  Wavelet sharpening (stronger, heavily gated)
    

*   Fine: 0.32
    
*   Mid: 0.22
    
*   Coarse: 0.09
    
*   Multiply by C^1.35
    
*   Additional rule: do not sharpen if snr < 4.0 in that neighborhood
    

1.  Micro-contrast
    

*   Radius: 22 px
    
*   Strength: 0.11
    
*   Only where C > 0.55
    
*   Never apply micro-contrast in the outer 10 px of the moon disk
    

1.  Halo controlCrisp threshold can be slightly higher since users asked for crispness, still needs restraint.
    

*   Overshoot threshold: 2.2%If exceeded:
    
*   Reduce fine gain by 35%
    
*   Reduce RL iterations by 2
    
*   Expand limb ring by 3 px
    
*   Re-run final sharpening pass once, no repeated loops
    

Crisp (video or burst) defaults

This is where Crisp should live, because it gives you real support for detail.

*   Keep top N frames:
    
    *   N = 20
        
*   Weighting exponent:
    
    *   weights proportional to sharpness^1.6
        
*   Optional drizzle 2x:
    
    *   Enable only if estimated subpixel motion coverage is good
        
    *   A quick heuristic: average alignment shift variance > 0.15 px in both axes across selected frames
        
*   After stacking:
    
    *   Base luma denoise strength: 0.14
        
    *   RL iterations: 7 (only if median(C) is high and clipping is low)
        
    *   Wavelet gains can stay at Crisp values or drop 10% if drizzle is enabled, since drizzle already increases perceived detail
        

The guardrails that keep both presets from looking synthetic

1.  “No clip, no lie” ruleIf highlights are clipped in the moon region beyond a tiny fraction, crater recovery is impossible. The app should shift into a conservative mode:
    

*   Lower contrast gains by 20–30%
    
*   Disable RL
    
*   Reduce fine sharpening band by 40%
    
*   Offer a message like: “Highlights clipped. Kept the result natural.”
    

1.  “Sky stays dark” ruleIf the user lifts shadows, the scene stops reading as a moon photo. Keep sky noise under control and do not push it toward gray. Give the user a sky slider if needed, default near zero.
    
2.  “Edge honesty” ruleThe limb is where fakeness screams. Always protect it:
    

*   Wide-ish limb ring
    
*   Halo tests
    
*   Separate processing for limb zone
    

1.  “Confidence gating everywhere”C is not a debug artifact. It is the product. It is how you honor the promise “not AI-looking.”
    

How to translate pain points into product features

A) Capture coaching that feels minimalUsers hate tutorials, they accept a small, precise nudge:

*   “Use video for detail” prompt on first run
    
*   Auto lock exposure to preserve highlights when the moon is detected
    
*   A simple stability meter that tells them when to hold still for 1 second
    

B) A Reality Meter users can understandOne indicator, not a technical report:

*   “Capture quality: Low / Medium / High”This maps to median(C), clipping rate, and sharpness score.It sets expectations and reduces the urge to crank sliders.
    

C) A single slider that maps to safe parametersEven with two presets, most users want one control:

*   Slider 0–100 changes RL iterations, wavelet gains, and micro-contrast in a coordinated way
    
*   The slider never overrides the guardrails
    

D) A share result that looks intentional

*   Default export is a tasteful crop with subtle vignette off by default
    
*   Optional composition: moon placed in a black frame with EXIF date, for people who want “astronomy style” without falsifying content
    

E) Speed and battery realityUsers abandon slow processing. Two tactics help:

*   Immediate preview at 512 px crop with the full pipeline
    
*   Background-quality render at full resolution as a second step, shown as “Finalizing” without turning it into a waiting room experience
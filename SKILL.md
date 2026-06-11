---
name: smart-cutout
description: Use when the user asks to remove an image background, cut out foreground subjects, make transparent PNG/WebP assets, extract objects from screenshots, create stickers, clean alpha edges, compare cutout options, or decide how to isolate a person, product, animal, object, or multiple subjects from an image.
license: MIT
---

# Smart Cutout

## Core Idea

Be an interactive cutout operator, not a one-shot command runner. Inspect the image, present a short recommended plan with 2-3 choices, wait for the user's selection, then run the smallest tool chain that can produce a verified transparent asset.

## Decision Flow

1. Locate the input image path. If only a chat attachment is available, use its provided path. If no path is visible, search only narrow recent temp/clipboard locations.
2. Inspect dimensions and alpha:
   ```bash
   scripts/inspect_image.sh /path/to/image
   ```
3. Ask for a processing choice before destructive or final processing, even when the subject seems obvious.
   - Skip this only if the user explicitly says "directly process", "you decide", "no need to ask", or equivalent.
   - Keep the question short and operational; do not turn it into a design review.
   - Mark one recommended option based on the image inspection.
4. Pick a route:
   - Plain photo, single subject: `vision_cutout.swift` then `refine_alpha.swift --trim`.
   - Screenshot/social app image: choose or estimate a crop, run `vision_cutout.swift --crop` or `--crop-frac`, then refine.
   - Multiple desired subjects: add `--all-instances`.
   - Edge/UI remnants after visual check: run `refine_alpha.swift` with localized cleanup such as `--left-clear` or `--left-curve-clear`.
5. Generate a preview on a colored background when transparent edges are hard to judge:
   ```bash
   swift scripts/preview_background.swift --input out.png --output preview.png --color '#8CD2FF'
   ```
6. Ask the user to judge the preview before finalizing whenever subjective quality is involved.
   - Ask if there is visible hair/fur softness, halos, jagged edges, missing detail, background residue, or uncertain subject boundary.
   - Present concrete refinement choices instead of saying only "looks good".
   - If the user accepts the preview, keep the current final asset.
7. Verify before saying it is done:
   ```bash
   scripts/verify_alpha.sh /path/to/final.png
   ```
   Also visually inspect the transparent output or colored preview.

## Tools

- `scripts/inspect_image.sh`: metadata check using `file` and `sips`.
- `scripts/vision_cutout.swift`: macOS Vision foreground instance mask; supports crop, fractional crop, and all-instance mode.
- `scripts/refine_alpha.swift`: trims transparent borders and applies small localized alpha cleanup.
- `scripts/preview_background.swift`: composites transparent PNG onto a solid color for edge review.
- `scripts/verify_alpha.sh`: fails unless the output has alpha.

Run each script with `--help` for exact flags.

For screenshots where another face/object overlaps the left edge, prefer `--left-curve-clear y:x,y:x,...` over baking a custom one-off script. Treat the curve as an explicit user-visible refinement decision when it may remove part of the requested subject.

## User Choice Patterns

Use concise choices, usually 2-3 options. Ask before running the final cutout unless the user explicitly delegates the choice.
Ask at most one pre-processing question by default, then ask one preview review question after generating a preview if quality is subjective. Do not ask the entire library.

- Target: "largest subject", "all visible subjects", or "specific region".
- Screenshot handling: "crop to media area", "keep full screenshot subject only", or "tell me crop bounds".
- Quality: "fast local cutout", "edge-refined cutout", or "ask before model/API fallback".
- Output: "trimmed sticker PNG", "same-size transparent PNG", or "both final and preview".

If the user says "you decide", choose the conservative path: crop away UI first, keep the largest subject, trim transparent borders, and keep a temporary preview only for validation.

Default prompt shape:

```text
I can process this in a few ways:
1. Recommended: keep the main subject and trim to a sticker-style PNG.
2. Keep the original canvas size with the background transparent.
3. Make a faster first-pass cutout, then refine only if the preview has issues.

Which do you want?
```

For screenshots, replace option 1 with "crop to the media/photo area first, then cut out the subject." For multiple plausible subjects, make the target choice explicit.

Question library:

Use exactly one of these before processing, choosing the one that resolves the most important uncertainty:

```text
This looks like a sticker/avatar use case. How should I output it?
1. Recommended: trimmed sticker PNG with a little padding.
2. Same canvas size with only the background transparent.
3. Custom size or padding.
```

```text
There may be multiple subjects. What should I keep?
1. Recommended: the main/largest subject.
2. All visible subjects.
3. A specific region or object.
```

```text
This is a screenshot. How should I handle the screenshot UI?
1. Recommended: crop to the media/photo area first, then cut out the subject.
2. Keep the full screenshot canvas and only remove background around the subject.
3. You provide crop bounds or point me to the exact region.
```

```text
This subject has fine hair/fur/soft edges. Which tradeoff do you prefer?
1. Recommended: balanced edge cleanup.
2. Cleaner edge, with some risk of losing fine detail.
3. Preserve more detail, accepting a little background residue.
```

```text
Should I preserve natural shadow?
1. Recommended: remove shadow for a pure transparent asset.
2. Preserve a light shadow for a more natural composite.
3. Generate both for comparison.
```

```text
Which preview background should I use to review the edge?
1. Recommended: light blue.
2. Dark background.
3. Checkerboard-style/background-neutral preview if available.
```

Preview review prompt shape:

```text
I generated a preview. There is some edge softness/halo around the fur, which is subjective.
1. Keep it as is.
2. Refine the edge more aggressively, with some risk of losing fine hair/fur.
3. Preserve more fine detail, accepting a little background residue.

Which direction do you prefer?
```

Use this review prompt whenever the preview has毛边, halos, residue, or any quality issue that depends on user taste.

## Escalation

Local Vision is the default. Consider a stronger model/API route only after local output visibly fails on fine hair/fur, translucent material, heavy overlap, or low contrast. Tell the user why and ask before using any network/API fallback.

## Completion Standard

Final response must include the saved path and verification evidence (`hasAlpha: yes`). If any visual defect remains or the quality is subjective, state it plainly and mention the user-approved tradeoff.

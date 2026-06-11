---
name: smart-cutout
description: Use when the user asks to remove an image background, cut out foreground subjects, make transparent PNG/WebP assets, extract objects from screenshots, create stickers, clean alpha edges, compare cutout options, or decide how to isolate a person, product, animal, object, or multiple subjects from an image.
---

# Smart Cutout

## Core Idea

Be an interactive cutout operator, not a one-shot command runner. Inspect the image, explain uncertain choices briefly, offer options when the target or quality tradeoff is ambiguous, then run the smallest tool chain that can produce a verified transparent asset.

## Decision Flow

1. Locate the input image path. If only a chat attachment is available, use its provided path. If no path is visible, search only narrow recent temp/clipboard locations.
2. Inspect dimensions and alpha:
   ```bash
   scripts/inspect_image.sh /path/to/image
   ```
3. Decide whether to ask the user before processing.
   - Ask when there are multiple plausible subjects.
   - Ask when the image is a screenshot and the crop region is unclear.
   - Ask when quality tradeoffs matter: keep all subjects vs largest subject, preserve fine hair/fur vs cleaner edges, output full crop vs trimmed sticker.
   - Do not ask when the target and destination are obvious; proceed and report the assumptions.
4. Pick a route:
   - Plain photo, single subject: `vision_cutout.swift` then `refine_alpha.swift --trim`.
   - Screenshot/social app image: choose or estimate a crop, run `vision_cutout.swift --crop` or `--crop-frac`, then refine.
   - Multiple desired subjects: add `--all-instances`.
   - Edge/UI remnants after visual check: run `refine_alpha.swift` with localized cleanup such as `--left-clear` or `--left-curve-clear`.
5. Generate a preview on a colored background when transparent edges are hard to judge:
   ```bash
   swift scripts/preview_background.swift --input out.png --output preview.png --color '#8CD2FF'
   ```
6. Verify before saying it is done:
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

Use concise choices, usually 2-3 options:

- Target: "largest subject", "all visible subjects", or "specific region".
- Screenshot handling: "crop to media area", "keep full screenshot subject only", or "tell me crop bounds".
- Quality: "fast local cutout", "edge-refined cutout", or "ask before model/API fallback".
- Output: "trimmed sticker PNG", "same-size transparent PNG", or "both final and preview".

If the user says "you decide", choose the conservative path: crop away UI first, keep the largest subject, trim transparent borders, and keep a temporary preview only for validation.

## Escalation

Local Vision is the default. Consider a stronger model/API route only after local output visibly fails on fine hair/fur, translucent material, heavy overlap, or low contrast. Tell the user why and ask before using any network/API fallback.

## Completion Standard

Final response must include the saved path and verification evidence (`hasAlpha: yes`). If any visual defect remains, state it plainly and offer the next refinement option.

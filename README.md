# Smart Cutout

Smart Cutout is a public Codex skill for interactive foreground extraction. It helps an agent inspect an image, choose a cutout strategy, ask the user for choices when the target is ambiguous, and produce a verified transparent PNG.

## Structure

```text
smart-cutout/
├── README.md
├── assets/
│   ├── cat-cutout-color-edge.png
│   └── cat-original.jpg
└── smart-cutout/
    ├── SKILL.md
    ├── agents/
    │   └── openai.yaml
    └── scripts/
        ├── inspect_image.sh
        ├── preview_background.swift
        ├── refine_alpha.swift
        ├── verify_alpha.sh
        └── vision_cutout.swift
```

`smart-cutout/SKILL.md` is the skill entrypoint. The scripts are small local tools used by the skill workflow.

## Installation

Install with GitHub CLI for Codex user scope:

```bash
gh skill install jinhuang712/smart-cutout smart-cutout --agent codex --scope user
```

Preview before installing:

```bash
gh skill preview jinhuang712/smart-cutout smart-cutout
```

Manual install with curl:

```bash
tmpdir="$(mktemp -d)"
curl -L https://github.com/jinhuang712/smart-cutout/archive/refs/heads/main.tar.gz \
  | tar -xz -C "$tmpdir"
mkdir -p ~/.codex/skills
rm -rf ~/.codex/skills/smart-cutout
cp -R "$tmpdir/smart-cutout-main/smart-cutout" ~/.codex/skills/smart-cutout
rm -rf "$tmpdir"
```

The manual command replaces an existing `~/.codex/skills/smart-cutout` install.

## Example

This example keeps the original canvas size and uses color-aware edge recovery to preserve more fine fur detail. The tradeoff is a slightly hazier edge because more semi-transparent source pixels are retained.

| Original | Transparent cutout |
| --- | --- |
| ![Original cat photo](assets/cat-original.jpg) | ![Cat cutout with transparent background](assets/cat-cutout-color-edge.png) |

## Requirements

- macOS
- Swift with AppKit and Vision framework support
- Built-in macOS `file` and `sips`

No Python package install is required for normal use.

## Validation

```bash
python3 /path/to/quick_validate.py /path/to/smart-cutout
swift smart-cutout/scripts/vision_cutout.swift --help
swift smart-cutout/scripts/refine_alpha.swift --help
swift smart-cutout/scripts/preview_background.swift --help
```

The final artifact should be verified with:

```bash
smart-cutout/scripts/verify_alpha.sh /path/to/output.png
```

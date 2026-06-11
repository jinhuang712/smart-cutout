# Smart Cutout

Smart Cutout is a public Codex skill for interactive foreground extraction. It helps an agent inspect an image, choose a cutout strategy, ask the user for choices when the target is ambiguous, and produce a verified transparent PNG.

## Structure

```text
smart-cutout/
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

`SKILL.md` is the skill entrypoint. The scripts are small local tools used by the skill workflow.

## Requirements

- macOS
- Swift with AppKit and Vision framework support
- Built-in macOS `file` and `sips`

No Python package install is required for normal use.

## Validation

```bash
python3 /path/to/quick_validate.py /path/to/smart-cutout
swift scripts/vision_cutout.swift --help
swift scripts/refine_alpha.swift --help
swift scripts/preview_background.swift --help
```

The final artifact should be verified with:

```bash
scripts/verify_alpha.sh /path/to/output.png
```

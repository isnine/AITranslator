# macOS Screenshot Pipeline (Local)

This project supports a fully automated macOS screenshot workflow **without Screen Recording permission**.

It has two stages:

1) **In-app export (offscreen render)** → generates clean UI PNGs
2) **Marketing composition** → adds background + headline/subtitle + shadow/rounding

> Scope: this doc describes the **macOS** pipeline only. iOS/iPad screenshots use Fastlane snapshot + frameit in `fastlane/screenshots/*`.

---

## Output directories

### Raw (in-app exported) screenshots

- `fastlane/macos_screenshots/<locale>/01_Home.png`
- `fastlane/macos_screenshots/<locale>/02_Conversation.png`
- `fastlane/macos_screenshots/<locale>/03_Actions.png`
- `fastlane/macos_screenshots/<locale>/04_Models.png`
- `fastlane/macos_screenshots/<locale>/05_Settings.png`

Currently we primarily run **en-US** during iteration.

### Final (marketing composed) screenshots

- `fastlane/macos_screenshots_marketing/<locale>/01_Home.png` … `05_Settings.png`

These are the **final deliverables** (same canvas size as required by Apple for macOS screenshots).

---

## 1) In-app export (offscreen render)

### Why

- No dependency on Screen Recording permission
- Never captures other desktop windows
- Deterministic output size

### How it works (high level)

When TLingo is launched with:

- `-FASTLANE_SNAPSHOT`
- `-MACOS_EXPORT_PATH <absolute_output_png_path>`

…the app exports a screenshot and terminates.

Internally we render SwiftUI views offscreen (via `NSHostingView` in an offscreen `NSWindow`) and write the PNG to disk.

### Supported flags

- `-SNAPSHOT_TAB actions|models|settings` → export the corresponding tab screen
- `-SNAPSHOT_CONVERSATION` → export the conversation screen
- `-SNAPSHOT_ACTION translate|grammar|polish` → for Home screen, choose which action to showcase (e.g. **polish** to show **diff highlighting**)

### Script

Run **in-app export** for macOS screenshots (en-US only):

```bash
cd ~/work/AITranslator
bash Scripts/capture_macos_screenshots_self.sh en-US
```

Notes:

- This script builds the macOS app (Debug) and exports `01~05` into `fastlane/macos_screenshots/en-US/`.
- Current export size is **1600×800** to match the marketing “shell” width and avoid distortion.

---

## 2) Marketing composition (A layout)

### What it does

Takes the raw screenshots and composites:

- heavier gradient background
- top headline/subtitle text
- rounded corners + shadow for the app screenshot

Text sources:

- `fastlane/screenshots/en-US/keyword.strings`
- `fastlane/screenshots/en-US/title.strings`

### Script

Generate **marketing composed** macOS screenshots (en-US):

```bash
cd ~/work/AITranslator
bash Scripts/frame_macos_marketing_en.sh
```

Outputs:

- `fastlane/macos_screenshots_marketing/en-US/*.png`

### Aspect ratio rules

- We avoid any stretching.
- The script uses a **cover** strategy (scale to fill + crop) so there are no left/right black bars.

---

## Typical workflow (en-US)

```bash
cd ~/work/AITranslator
bash Scripts/capture_macos_screenshots_self.sh en-US
bash Scripts/frame_macos_marketing_en.sh
open fastlane/macos_screenshots_marketing/en-US
```

---

## Troubleshooting

### The screenshot includes other windows

You are using a screen-capture based workflow. This macOS pipeline avoids that by exporting offscreen.
Make sure you’re using:

- `Scripts/capture_macos_screenshots_self.sh`

…and that your final images are from:

- `fastlane/macos_screenshots_marketing/...`

### Black app content area in the composed poster

Usually an alpha/mask composition issue. The composition script applies rounding + shadow in two steps to preserve RGB.
Re-run:

```bash
bash Scripts/frame_macos_marketing_en.sh
```

### Wrong layout / missing diff highlight

Use the Home action selector flag:

- `-SNAPSHOT_ACTION polish`

The default script already sets Home to `polish` to showcase diff.

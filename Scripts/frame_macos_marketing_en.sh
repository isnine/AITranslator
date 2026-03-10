#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IN_DIR="$PROJECT_DIR/fastlane/macos_screenshots/en-US"
OUT_DIR="$PROJECT_DIR/fastlane/macos_screenshots_marketing/en-US"
KW_JSON="$(/usr/bin/plutil -convert json -o - "$PROJECT_DIR/fastlane/screenshots/en-US/keyword.strings")"
TT_JSON="$(/usr/bin/plutil -convert json -o - "$PROJECT_DIR/fastlane/screenshots/en-US/title.strings")"

mkdir -p "$OUT_DIR"

# canvas size (Apple macOS screenshot)
W=1280
H=800

# layout
TOP_H=240        # top text band
PAD_X=92

# app screenshot placement
APP_W=1100
APP_H=540
APP_X=$(( (W-APP_W)/2 ))
APP_Y=210
RADIUS=28
SHADOW_Y=10

# background
BG1="#0B0D12"
BG2="#161B28"
ACC="#4F7CFF"

json_get() {
  local json="$1"; local key="$2"
  /usr/bin/python3 -c 'import json,sys; j=json.loads(sys.argv[1]); print(j.get(sys.argv[2],""))' "$json" "$key"
}

round_mask() {
  local w="$1"; local h="$2"; local r="$3"; local out="$4"
  # Black background with a white rounded-rect. No alpha.
  magick -size "${w}x${h}" xc:black \
    -fill white \
    -draw "roundrectangle 0,0 $((w-1)),$((h-1)) ${r},${r}" \
    -alpha off \
    "$out"
}

render_one() {
  local key="$1"
  local in_png="$IN_DIR/${key}.png"
  local out_png="$OUT_DIR/${key}.png"

  if [ ! -f "$in_png" ]; then
    echo "Missing input: $in_png" >&2
    return 1
  fi

  local headline subtitle
  headline=$(json_get "$KW_JSON" "$key")
  subtitle=$(json_get "$TT_JSON" "$key")

  # prepare app image with rounded corners + shadow
  local tmp_app="/tmp/macos_app_${key}.png"
  local tmp_mask="/tmp/macos_mask_${key}.png"
  round_mask "$APP_W" "$APP_H" "$RADIUS" "$tmp_mask"

  # Step 1: rounded-corner clip (keep RGB)
  local tmp_round="/tmp/macos_round_${key}.png"
  # Cover: keep aspect ratio, fill APP_W x APP_H (no black bars), then crop.
  magick "$in_png" -resize "${APP_W}x${APP_H}^" \
    -gravity center -extent "${APP_W}x${APP_H}" \
    -alpha set \
    \( "$tmp_mask" \) -compose CopyOpacity -composite \
    "$tmp_round"

  # Step 2: shadow + merge
  magick "$tmp_round" \
    -background none \
    \( +clone -background "#00000080" -shadow 40x18+0+${SHADOW_Y} \) \
    +swap -background none -layers merge +repage \
    "$tmp_app"

  # background
  magick -size "${W}x${H}" gradient:"$BG1"-"$BG2" \
    -colorspace sRGB \
    \( +clone -fill "$ACC" -colorize 8% \) -compose overlay -composite \
    /tmp/macos_bg_${key}.png

  # text
  # Use system fonts; if missing, ImageMagick will fallback.
  local font_head="/System/Library/Fonts/Supplemental/Arial Bold.ttf"
  local font_sub="/System/Library/Fonts/Supplemental/Arial.ttf"

  magick /tmp/macos_bg_${key}.png \
    \( -size "$((W-2*PAD_X))x${TOP_H}" xc:none \
      -font "$font_head" -pointsize 58 -fill white -gravity northwest \
      -annotate +0+30 "$headline" \
      -font "$font_sub" -pointsize 30 -fill "#C7CCDA" -gravity northwest \
      -annotate +0+115 "$subtitle" \
    \) -geometry +${PAD_X}+20 -composite \
    "$tmp_app" -geometry +${APP_X}+${APP_Y} -composite \
    -strip \
    "$out_png"

  echo "Wrote: $out_png"
}

for key in 01_Home 02_Conversation 03_Actions 04_Models 05_Settings; do
  render_one "$key"
done

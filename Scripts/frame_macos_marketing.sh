#!/bin/bash
#
# Marketing-style macOS screenshot composition (all locales).
# Takes raw screenshots and composites:
#   - Dark gradient background
#   - Headline + subtitle from keyword.strings / title.strings
#   - Rounded corners + drop shadow on the app screenshot
#
# Input:  screenshots/macos/<locale>/0X_*.png
# Text:   screenshots/ios/<locale>/{keyword.strings,title.strings}
# Output: screenshots/macos_marketing/<locale>/0X_*.png
#
# Usage:
#   ./Scripts/frame_macos_marketing.sh              # all locales that have raw screenshots
#   ./Scripts/frame_macos_marketing.sh en-US         # single locale
#   ./Scripts/frame_macos_marketing.sh en-US zh-Hans  # multiple locales
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IN_BASE="$PROJECT_DIR/screenshots/macos"
OUT_BASE="$PROJECT_DIR/screenshots/macos_marketing"
TEXT_BASE="$PROJECT_DIR/screenshots/ios"

# Canvas size (Apple macOS App Store accepted)
W=1280
H=800

# Layout
TOP_H=240
PAD_X=92

# App screenshot placement (within the MacBook frame)
APP_W=1000
APP_H=500
APP_X=$(( (W - APP_W) / 2 ))
APP_Y=155
RADIUS=8
SHADOW_Y=10

# MacBook bezel dimensions (drawn around the screenshot)
BEZEL_COLOR="#1C1C1E"
BEZEL_TOP=18
BEZEL_SIDE=18
BEZEL_BOTTOM=18
BEZEL_RADIUS=14
# Bottom hinge/base bar
HINGE_H=14
HINGE_W=$((APP_W + 2 * BEZEL_SIDE + 80))
HINGE_COLOR="#2C2C2E"
HINGE_NOTCH_W=160
HINGE_NOTCH_H=6
HINGE_NOTCH_COLOR="#3A3A3C"

# Background colors
BG1="#0B0D12"
BG2="#161B28"
ACC="#4F7CFF"

# Fonts (system fallbacks)
FONT_HEAD="/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_SUB="/System/Library/Fonts/Supplemental/Arial.ttf"

# CJK font override (PingFang for CJK locales)
FONT_CJK_HEAD="$PROJECT_DIR/screenshots/fonts/PingFangSC-Semibold.ttf"
FONT_CJK_SUB="$PROJECT_DIR/screenshots/fonts/PingFangSC-Regular.ttf"

KEYS=("01_Home" "02_Conversation" "03_Actions" "04_Models" "05_Settings" "06_Polish")

log() { echo "🖼  $1" >&2; }
err() { echo "❌ $1" >&2; }

# Determine if a locale needs CJK fonts
is_cjk_locale() {
  local locale="$1"
  case "$locale" in
    zh-*|ja|ko) return 0 ;;
    *) return 1 ;;
  esac
}

# Parse .strings file: "KEY" = "VALUE";
strings_get() {
  local file="$1"
  local key="$2"
  python3 -c "
import re, sys
try:
    s = open(sys.argv[1], 'r', encoding='utf-8').read()
except FileNotFoundError:
    sys.exit(0)
pat = re.compile(r'\"' + re.escape(sys.argv[2]) + r'\"\s*=\s*\"(.*?)\"\s*;')
m = pat.search(s)
if m:
    print(m.group(1))
" "$file" "$key" 2>/dev/null || true
}

# Generate rounded-corner mask
round_mask() {
  local w="$1" h="$2" r="$3" out="$4"
  magick -size "${w}x${h}" xc:black \
    -fill white \
    -draw "roundrectangle 0,0 $((w-1)),$((h-1)) ${r},${r}" \
    -alpha off \
    "$out"
}

render_one() {
  local locale="$1"
  local key="$2"

  local in_png="$IN_BASE/$locale/${key}.png"
  local out_dir="$OUT_BASE/$locale"
  local out_png="$out_dir/${key}.png"

  if [ ! -f "$in_png" ]; then
    err "Missing input: $in_png"
    return 1
  fi

  mkdir -p "$out_dir"

  # Read localized text
  local headline subtitle
  headline=$(strings_get "$TEXT_BASE/$locale/keyword.strings" "$key")
  subtitle=$(strings_get "$TEXT_BASE/$locale/title.strings" "$key")

  # Fallback to en-US if locale text missing
  if [ -z "$headline" ]; then
    headline=$(strings_get "$TEXT_BASE/en-US/keyword.strings" "$key")
  fi
  if [ -z "$subtitle" ]; then
    subtitle=$(strings_get "$TEXT_BASE/en-US/title.strings" "$key")
  fi
  # Last resort
  if [ -z "$headline" ]; then headline="$key"; fi
  if [ -z "$subtitle" ]; then subtitle=""; fi

  # Select fonts based on locale
  local font_h="$FONT_HEAD"
  local font_s="$FONT_SUB"
  if is_cjk_locale "$locale"; then
    if [ -f "$FONT_CJK_HEAD" ]; then font_h="$FONT_CJK_HEAD"; fi
    if [ -f "$FONT_CJK_SUB" ]; then font_s="$FONT_CJK_SUB"; fi
  fi

  # Temp files
  local tmp_screen="/tmp/macos_screen_${key}.png"
  local tmp_bezel="/tmp/macos_bezel_${key}.png"
  local tmp_device="/tmp/macos_device_${key}.png"
  local tmp_app="/tmp/macos_app_${key}.png"
  local tmp_bg="/tmp/macos_bg_${key}.png"

  # Full bezel outer dimensions
  local bezel_w=$((APP_W + 2 * BEZEL_SIDE))
  local bezel_h=$((APP_H + BEZEL_TOP + BEZEL_BOTTOM))

  # 1. Resize screenshot to screen area (fit, no crop) with slight rounding
  magick "$in_png" -resize "${APP_W}x${APP_H}!" \
    \( -size "${APP_W}x${APP_H}" xc:black -fill white \
       -draw "roundrectangle 0,0 $((APP_W-1)),$((APP_H-1)) ${RADIUS},${RADIUS}" \
       -alpha off \) \
    -alpha set -compose CopyOpacity -composite \
    "$tmp_screen"

  # 2. Draw MacBook bezel (rounded rectangle frame)
  magick -size "${bezel_w}x${bezel_h}" xc:none \
    -fill "${BEZEL_COLOR}" \
    -draw "roundrectangle 0,0 $((bezel_w-1)),$((bezel_h-1)) ${BEZEL_RADIUS},${BEZEL_RADIUS}" \
    "$tmp_bezel"

  # 3. Composite screen into bezel
  magick "$tmp_bezel" \
    "$tmp_screen" -geometry "+${BEZEL_SIDE}+${BEZEL_TOP}" -composite \
    "$tmp_bezel"

  # 4. Add bottom hinge/base bar below bezel
  local hinge_x=$(( (bezel_w - HINGE_W) / 2 ))
  local total_h=$((bezel_h + HINGE_H))
  local notch_x=$(( (HINGE_W - HINGE_NOTCH_W) / 2 ))
  local notch_y=$(( (HINGE_H - HINGE_NOTCH_H) / 2 ))
  magick -size "${bezel_w}x${total_h}" xc:none \
    "$tmp_bezel" -geometry "+0+0" -composite \
    -fill "${HINGE_COLOR}" \
    -draw "roundrectangle ${hinge_x},$((bezel_h)) $((hinge_x + HINGE_W - 1)),$((total_h - 1)) 4,4" \
    -fill "${HINGE_NOTCH_COLOR}" \
    -draw "roundrectangle $((hinge_x + notch_x)),$((bezel_h + notch_y)) $((hinge_x + notch_x + HINGE_NOTCH_W - 1)),$((bezel_h + notch_y + HINGE_NOTCH_H - 1)) 3,3" \
    "$tmp_device"

  # 5. Drop shadow on device
  magick "$tmp_device" \
    -background none \
    \( +clone -background "#00000060" -shadow 30x12+0+${SHADOW_Y} \) \
    +swap -background none -layers merge +repage \
    "$tmp_app"

  # 6. Gradient background
  magick -size "${W}x${H}" gradient:"${BG1}"-"${BG2}" \
    -colorspace sRGB \
    \( +clone -fill "$ACC" -colorize 8% \) -compose overlay -composite \
    "$tmp_bg"

  # Device placement: center horizontally, position below text area
  local device_info
  device_info=$(magick identify -format "%w %h" "$tmp_app")
  local dev_w dev_h
  dev_w=$(echo "$device_info" | awk '{print $1}')
  dev_h=$(echo "$device_info" | awk '{print $2}')
  local dev_x=$(( (W - dev_w) / 2 ))
  local dev_y=$((APP_Y))

  # 7. Composite: bg + text + MacBook device
  magick "$tmp_bg" \
    \( -size "$((W - 2 * PAD_X))x${TOP_H}" xc:none \
      -font "$font_h" -pointsize 58 -fill white -gravity northwest \
      -annotate +0+30 "$headline" \
      -font "$font_s" -pointsize 30 -fill "#C7CCDA" -gravity northwest \
      -annotate +0+115 "$subtitle" \
    \) -geometry "+${PAD_X}+20" -composite \
    "$tmp_app" -geometry "+${dev_x}+${dev_y}" -composite \
    -strip \
    "$out_png"

  # Cleanup temp files
  rm -f "$tmp_screen" "$tmp_bezel" "$tmp_device" "$tmp_app" "$tmp_bg"

  log "OK: $out_png"
}

# Determine locales
if [ $# -gt 0 ]; then
  LOCALES=("$@")
else
  # Auto-discover locales from raw screenshots directory
  LOCALES=()
  for dir in "$IN_BASE"/*/; do
    if [ -d "$dir" ]; then
      locale=$(basename "$dir")
      LOCALES+=("$locale")
    fi
  done
fi

if [ ${#LOCALES[@]} -eq 0 ]; then
  err "No locales found in $IN_BASE"
  exit 1
fi

log "Locales: ${LOCALES[*]}"
log "Input:   $IN_BASE"
log "Output:  $OUT_BASE"

FAILED=()

for locale in "${LOCALES[@]}"; do
  log "=== $locale ==="
  for key in "${KEYS[@]}"; do
    render_one "$locale" "$key" || FAILED+=("$locale:$key")
  done
done

log "Done."
if [ ${#FAILED[@]} -gt 0 ]; then
  err "Failures: ${FAILED[*]}"
  exit 1
fi

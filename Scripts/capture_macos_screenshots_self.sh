#!/bin/bash
#
# macOS screenshots without Screen Recording permission:
# The app exports its own window content to PNG via -MACOS_EXPORT_PATH.
#
# Output:
#   fastlane/macos_screenshots/<locale>/0X_*.png
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/AITranslator.xcodeproj"
SCHEME="TLingo"
APP_NAME="TLingo"
OUTPUT_BASE="$PROJECT_DIR/fastlane/macos_screenshots"

TARGET_W=1600
TARGET_H=800

DEFAULT_LOCALES=(
  "en-US"
  "zh-Hans"
  "zh-Hant"
  "ja"
  "ko"
  "de-DE"
  "fr-FR"
  "es-ES"
  "it"
  "pt-BR"
  "ar-SA"
  "da"
  "no"
  "nl-NL"
  "sv"
  "tr"
  "id"
)

# Usage: ./capture_macos_screenshots_self.sh [locale]
# - No args: capture all default locales
# - With arg: capture only that locale (e.g. en-US)
if [ $# -gt 0 ]; then
  LOCALES=("$1")
else
  LOCALES=("${DEFAULT_LOCALES[@]}")
fi

log(){ echo "🖥️  $1" >&2; }

kill_app() {
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.5
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    pkill -9 -x "$APP_NAME" 2>/dev/null || true
    sleep 0.5
  fi
  # Wait until the process is fully gone (avoids `open -a` reusing a dying process)
  for _w in $(seq 1 10); do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
    sleep 0.3
  done
}

build_and_find_app() {
  log "Building $SCHEME for macOS (Debug)…"
  xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=macOS,arch=arm64" \
    -quiet 2>&1 | tail -n 20 >&2

  local build_dir
  build_dir=$(xcodebuild -showBuildSettings \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=macOS,arch=arm64" \
    2>/dev/null | awk -F' = ' '/TARGET_BUILD_DIR/{print $2; exit}')

  echo "$build_dir/$APP_NAME.app"
}

apple_lang_args_for_locale() {
  local locale="$1"
  case "$locale" in
    "en-US")  echo "-AppleLanguages (en) -AppleLocale en_US" ;;
    "zh-Hans") echo "-AppleLanguages (zh-Hans) -AppleLocale zh_Hans" ;;
    "zh-Hant") echo "-AppleLanguages (zh-Hant) -AppleLocale zh_Hant" ;;
    "ja")     echo "-AppleLanguages (ja) -AppleLocale ja_JP" ;;
    "ko")     echo "-AppleLanguages (ko) -AppleLocale ko_KR" ;;
    "de-DE")  echo "-AppleLanguages (de) -AppleLocale de_DE" ;;
    "fr-FR")  echo "-AppleLanguages (fr) -AppleLocale fr_FR" ;;
    "es-ES")  echo "-AppleLanguages (es) -AppleLocale es_ES" ;;
    "it")     echo "-AppleLanguages (it) -AppleLocale it_IT" ;;
    "pt-BR")  echo "-AppleLanguages (pt-BR) -AppleLocale pt_BR" ;;
    "ar-SA")  echo "-AppleLanguages (ar) -AppleLocale ar_SA" ;;
    "da")     echo "-AppleLanguages (da) -AppleLocale da_DK" ;;
    "no")     echo "-AppleLanguages (nb) -AppleLocale nb_NO" ;;
    "nl-NL")  echo "-AppleLanguages (nl) -AppleLocale nl_NL" ;;
    "sv")     echo "-AppleLanguages (sv) -AppleLocale sv_SE" ;;
    "tr")     echo "-AppleLanguages (tr) -AppleLocale tr_TR" ;;
    "id")     echo "-AppleLanguages (id) -AppleLocale id_ID" ;;
    *) return 1 ;;
  esac
}

capture_one() {
  local app_path="$1"
  local locale="$2"
  local name="$3"   # 01_Home etc
  shift 3
  local extra=("$@")

  local out_dir="$OUTPUT_BASE/$locale"
  mkdir -p "$out_dir"
  local out_path="$out_dir/${name}.png"
  # Remove any stale file so we don't mistake an old export as success
  rm -f "$out_path" 2>/dev/null || true

  # Export to /tmp first to avoid macOS TCC file-access permission prompts,
  # then move the file to the final destination.
  local tmp_path="/tmp/tlingo_export_${name}.png"
  rm -f "$tmp_path" 2>/dev/null || true

  # shell-split args string into array
  read -r -a LANG_ARGS <<< "$(apple_lang_args_for_locale "$locale")"

  # bash 3.2 + set -u: empty arrays must be initialized
  local extra_args=()
  if [ ${#extra[@]} -gt 0 ]; then
    extra_args=("${extra[@]}")
  fi

  kill_app

  # Clear any stale status before launch
  rm -f /tmp/tlingo_export_status.txt 2>/dev/null || true

  # Run the binary directly instead of `open -a` to avoid Launch Services
  # reusing a dying process or swallowing arguments.
  local bin_path="$app_path/Contents/MacOS/$APP_NAME"

  log "Exporting $locale/$name -> $out_path"
  if [ ${#extra[@]} -gt 0 ]; then
    "$bin_path" \
      -FASTLANE_SNAPSHOT \
      -MACOS_EXPORT_PATH "$tmp_path" \
      "${extra[@]}" \
      "${LANG_ARGS[@]}" >/dev/null 2>&1 &
  else
    "$bin_path" \
      -FASTLANE_SNAPSHOT \
      -MACOS_EXPORT_PATH "$tmp_path" \
      "${LANG_ARGS[@]}" >/dev/null 2>&1 &
  fi

  # Wait up to 25s for tmp_path
  for i in $(seq 1 50); do
    if [ -f "$tmp_path" ]; then
      break
    fi
    sleep 0.5
  done

  if [ ! -f "$tmp_path" ]; then
    log "ERROR: timeout waiting for export ($out_path)"
    if [ -f /tmp/tlingo_export_status.txt ]; then
      log "Status: $(tr '\n' ' ' < /tmp/tlingo_export_status.txt | head -c 200)"
    fi
    return 1
  fi

  # Move from /tmp to final destination
  mv -f "$tmp_path" "$out_path"

  # quick sanity check
  local w h
  w=$(sips -g pixelWidth "$out_path" 2>/dev/null | awk '/pixelWidth/ {print $2}')
  h=$(sips -g pixelHeight "$out_path" 2>/dev/null | awk '/pixelHeight/ {print $2}')
  log "Saved ($w x $h)"
  if [ "$w" != "$TARGET_W" ] || [ "$h" != "$TARGET_H" ]; then
    log "WARNING: expected ${TARGET_W}x${TARGET_H}"
  fi
  return 0
}

APP_PATH=$(build_and_find_app)
if [ ! -d "$APP_PATH" ]; then
  echo "App not found: $APP_PATH" >&2
  exit 1
fi

log "App: $APP_PATH"

for locale in "${LOCALES[@]}"; do
  log "=== $locale ==="
  # Home screenshot: use polish action (translate hangs in offscreen render)
  capture_one "$APP_PATH" "$locale" "01_Home" -SNAPSHOT_ACTION polish || exit 1
  capture_one "$APP_PATH" "$locale" "02_Conversation" -SNAPSHOT_CONVERSATION || exit 1
  capture_one "$APP_PATH" "$locale" "03_Actions" -SNAPSHOT_TAB actions || exit 1
  capture_one "$APP_PATH" "$locale" "04_Models" -SNAPSHOT_TAB models || exit 1
  capture_one "$APP_PATH" "$locale" "05_Settings" -SNAPSHOT_TAB settings || exit 1
  # Polish screenshot: same view as 01_Home, different marketing text
  cp "$OUTPUT_BASE/$locale/01_Home.png" "$OUTPUT_BASE/$locale/06_Polish.png"

done

log "Done ✅"

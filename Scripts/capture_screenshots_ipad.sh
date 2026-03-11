#!/bin/bash
set -euo pipefail

# iPad screenshot capture (all locales) for App Store — TLingo

# ─── Configuration ───────────────────────────────────────────────
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIM_UDID="1A6A6179-FF5A-40A8-971B-0E5BEBD14D4B"
SIM_NAME="Apple iPad Pro (12.9-inch) (4th generation)"
SCHEME="TLingoUITests"
PROJECT="$PROJECT_DIR/AITranslator.xcodeproj"
OUTPUT_DIR="$PROJECT_DIR/fastlane/screenshots"
CACHE_DIR="$HOME/Library/Caches/tools.fastlane"
SCREENSHOTS_CACHE="$CACHE_DIR/screenshots"

LANGUAGES=(
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

# ─── Helpers ─────────────────────────────────────────────────────
log() { echo "📸 $1"; }
err() { echo "❌ $1" >&2; }

cleanup_screenshots_cache() {
  rm -rf "$SCREENSHOTS_CACHE"
  mkdir -p "$SCREENSHOTS_CACHE"
}

write_snapshot_config() {
  local lang="$1"
  mkdir -p "$CACHE_DIR"
  echo "$lang" > "$CACHE_DIR/language.txt"
  echo "$lang" > "$CACHE_DIR/locale.txt"
  echo "-FASTLANE_SNAPSHOT" > "$CACHE_DIR/snapshot-launch_arguments.txt"
}

collect_screenshots() {
  local lang="$1"
  local dest="$OUTPUT_DIR/$lang"
  mkdir -p "$dest"

  local count=0
  for f in "$SCREENSHOTS_CACHE"/*.png; do
    [ -f "$f" ] || continue
    cp "$f" "$dest/"
    count=$((count + 1))
  done
  echo "$count"
}

# ─── Main ────────────────────────────────────────────────────────
log "Starting iPad screenshot capture for ${#LANGUAGES[@]} languages"
log "Simulator: $SIM_NAME ($SIM_UDID)"

log "Booting simulator..."
xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
sleep 2

log "Setting clean status bar..."
xcrun simctl status_bar "$SIM_UDID" override \
  --time "9:41" \
  --dataNetwork wifi \
  --wifiMode active \
  --batteryState charged \
  --batteryLevel 100 2>/dev/null || true

log "Building UI tests (iPad derived data)..."
xcodebuild build-for-testing \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -derivedDataPath "$PROJECT_DIR/build/SnapshotDerivedData-iPad" \
  -skipMacroValidation \
  -quiet 2>&1 | tail -5

BUILD_EXIT=${PIPESTATUS[0]}
if [ "$BUILD_EXIT" -ne 0 ]; then
  err "Build failed with exit code $BUILD_EXIT"
  exit 1
fi
log "Build succeeded ✅"

TOTAL_SCREENSHOTS=0
FAILED_LANGS=()

for lang in "${LANGUAGES[@]}"; do
  log "━━━ Capturing iPad: $lang ━━━"

  write_snapshot_config "$lang"
  cleanup_screenshots_cache

  # Set simulator language/locale
  xcrun simctl spawn "$SIM_UDID" defaults write "Apple Global Domain" AppleLanguages -array "$lang" 2>/dev/null || true
  xcrun simctl spawn "$SIM_UDID" defaults write "Apple Global Domain" AppleLocale -string "$lang" 2>/dev/null || true

  if xcodebuild test-without-building \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "platform=iOS Simulator,id=$SIM_UDID" \
    -derivedDataPath "$PROJECT_DIR/build/SnapshotDerivedData-iPad" \
    -skipMacroValidation \
    -quiet 2>&1 | tail -3; then

    count=$(collect_screenshots "$lang")
    log "$lang: $count screenshots captured ✅"
    TOTAL_SCREENSHOTS=$((TOTAL_SCREENSHOTS + count))
  else
    err "$lang: Tests failed ⚠️"
    FAILED_LANGS+=("$lang")
    count=$(collect_screenshots "$lang")
    if [ "$count" -gt 0 ]; then
      log "$lang: Recovered $count screenshots despite test failure"
      TOTAL_SCREENSHOTS=$((TOTAL_SCREENSHOTS + count))
    fi
  fi

done

xcrun simctl status_bar "$SIM_UDID" clear 2>/dev/null || true

echo ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "iPad screenshot capture complete!"
log "Total screenshots: $TOTAL_SCREENSHOTS"
log "Languages: ${#LANGUAGES[@]} attempted"
if [ ${#FAILED_LANGS[@]} -gt 0 ]; then
  err "Failed languages: ${FAILED_LANGS[*]}"
fi
log "Output: $OUTPUT_DIR"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

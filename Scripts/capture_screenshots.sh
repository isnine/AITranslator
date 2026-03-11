#!/bin/bash
set -euo pipefail

# iPhone screenshot capture (all locales) for App Store — TLingo

# ─── Configuration ───────────────────────────────────────────────
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIM_UDID="C44072F7-A10C-4C39-96D8-CC1AEE321722"
SIM_NAME="11PRO MAX - App Store"
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
log "Starting iPhone screenshot capture for ${#LANGUAGES[@]} languages"
log "Simulator: $SIM_NAME ($SIM_UDID)"

# Boot simulator
log "Booting simulator..."
xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
sleep 2

# Override status bar
log "Setting clean status bar..."
xcrun simctl status_bar "$SIM_UDID" override \
  --time "9:41" \
  --dataNetwork wifi \
  --wifiMode active \
  --batteryState charged \
  --batteryLevel 100 2>/dev/null || true

# Build UI tests once
log "Building UI tests (this may take a few minutes)..."
xcodebuild build-for-testing \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -derivedDataPath "$PROJECT_DIR/build/SnapshotDerivedData" \
  -skipMacroValidation \
  -quiet 2>&1 | tail -5

BUILD_EXIT=${PIPESTATUS[0]}
if [ "$BUILD_EXIT" -ne 0 ]; then
  err "Build failed with exit code $BUILD_EXIT"
  exit 1
fi
log "Build succeeded ✅"

# Capture screenshots for each language
TOTAL_SCREENSHOTS=0
FAILED_LANGS=()

for lang in "${LANGUAGES[@]}"; do
  log "━━━ Capturing iPhone: $lang ━━━"

  # Set language
  write_snapshot_config "$lang"
  cleanup_screenshots_cache

  # Also set simulator language via simctl for system UI
  xcrun simctl spawn "$SIM_UDID" defaults write "Apple Global Domain" AppleLanguages -array "$lang" 2>/dev/null || true
  xcrun simctl spawn "$SIM_UDID" defaults write "Apple Global Domain" AppleLocale -string "$lang" 2>/dev/null || true

  # Run tests
  if xcodebuild test-without-building \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "platform=iOS Simulator,id=$SIM_UDID" \
    -derivedDataPath "$PROJECT_DIR/build/SnapshotDerivedData" \
    -skipMacroValidation \
    -quiet 2>&1 | tail -3; then

    # Collect screenshots
    count=$(collect_screenshots "$lang")
    log "$lang: $count screenshots captured ✅"
    TOTAL_SCREENSHOTS=$((TOTAL_SCREENSHOTS + count))
  else
    err "$lang: Tests failed ⚠️"
    FAILED_LANGS+=("$lang")
    # Still try to collect any screenshots that were taken
    count=$(collect_screenshots "$lang")
    if [ "$count" -gt 0 ]; then
      log "$lang: Recovered $count screenshots despite test failure"
      TOTAL_SCREENSHOTS=$((TOTAL_SCREENSHOTS + count))
    fi
  fi
done

# Clear status bar override
xcrun simctl status_bar "$SIM_UDID" clear 2>/dev/null || true

# Summary
echo ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "iPhone screenshot capture complete!"
log "Total screenshots: $TOTAL_SCREENSHOTS"
log "Languages: ${#LANGUAGES[@]} attempted"
if [ ${#FAILED_LANGS[@]} -gt 0 ]; then
  err "Failed languages: ${FAILED_LANGS[*]}"
fi
log "Output: $OUTPUT_DIR"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

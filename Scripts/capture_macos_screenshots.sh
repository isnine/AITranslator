#!/bin/bash
#
# Automated macOS App Store screenshot capture for TLingo
# Captures 5 screens for each locale at 1280x800 (non-Retina display)
#
# Usage: ./scripts/capture_macos_screenshots.sh [locale]
# - No args: captures all 5 locales
# - With arg: captures only the specified locale

set -euo pipefail

APP_PATH="/Users/xiaozwan/Library/Developer/Xcode/DerivedData/AITranslator-hfcqteynhjuldgcoznlnpxuziinq/Build/Products/Debug/TLingo.app"
OUTPUT_BASE="/Users/xiaozwan/work/AITranslator/fastlane/macos_screenshots"
KILL_NAME="TLingo"

# Target screenshot size (1280x800 = valid App Store macOS size)
TARGET_WIDTH=1280
TARGET_HEIGHT=800

# Determine which locales to capture
if [ $# -gt 0 ]; then
    LOCALES=("$1")
else
    LOCALES=("en-US" "zh-Hans" "ja" "ko" "de")
fi

echo "=== TLingo macOS Screenshot Capture ==="
echo "App: $APP_PATH"
echo "Output: $OUTPUT_BASE"
echo "Target size: ${TARGET_WIDTH}x${TARGET_HEIGHT} px"
echo "Locales: ${LOCALES[*]}"
echo ""

# Kill the app if running
kill_app() {
    pkill -x "$KILL_NAME" 2>/dev/null || true
    sleep 2
    # Force kill if still alive
    if pgrep -x "$KILL_NAME" >/dev/null 2>&1; then
        pkill -9 -x "$KILL_NAME" 2>/dev/null || true
        sleep 1
    fi
}

# Get the on-screen window bounds for TLingo (x,y,w,h in pixels)
get_window_bounds() {
    swift -e '
import Cocoa
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
if let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
    for window in windowList {
        let owner = window["kCGWindowOwnerName"] as? String ?? ""
        let layer = window["kCGWindowLayer"] as? Int ?? 999
        if owner.hasPrefix("TLingo") && layer == 0 {
            if let b = window["kCGWindowBounds"] as? [String: Any],
               let x = b["X"] as? Int, let y = b["Y"] as? Int,
               let w = b["Width"] as? Int, let h = b["Height"] as? Int {
                print("\(x),\(y),\(w),\(h)")
            }
            break
        }
    }
}
' 2>/dev/null
}

# Wait for TLingo window to appear (with timeout)
wait_for_window() {
    local max_wait=20
    local waited=0
    while [ $waited -lt $max_wait ]; do
        local bounds
        bounds=$(get_window_bounds)
        if [ -n "$bounds" ]; then
            echo "  Window appeared after ${waited}s"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    echo "  ERROR: Window did not appear within ${max_wait}s"
    return 1
}

# Capture screenshot: full desktop + crop to window region
capture_screenshot() {
    local output_path="$1"
    local temp_full="/tmp/tlingo_full_desktop.png"

    # Let animations settle
    sleep 1

    # Get window bounds (in pixels, non-Retina = 1:1)
    local bounds
    bounds=$(get_window_bounds)

    if [ -z "$bounds" ]; then
        echo "  ERROR: Could not find TLingo window bounds"
        return 1
    fi

    IFS=',' read -r WX WY WW WH <<< "$bounds"
    echo "  Window bounds (px): ${WX},${WY} ${WW}x${WH}"

    # Capture full desktop
    screencapture -x "$temp_full" 2>&1
    if [ ! -f "$temp_full" ]; then
        echo "  ERROR: Full desktop capture failed"
        return 1
    fi

    # Crop to window region (no Retina scaling needed on this display)
    magick "$temp_full" -crop "${WW}x${WH}+${WX}+${WY}" +repage "$output_path" 2>&1

    rm -f "$temp_full"

    if [ -f "$output_path" ]; then
        local w h
        w=$(sips -g pixelWidth "$output_path" 2>/dev/null | awk '/pixelWidth/ {print $2}')
        h=$(sips -g pixelHeight "$output_path" 2>/dev/null | awk '/pixelHeight/ {print $2}')
        echo "  Captured: $(basename "$output_path") (${w}x${h})"

        # Validate dimensions
        if [ "$w" != "$TARGET_WIDTH" ] || [ "$h" != "$TARGET_HEIGHT" ]; then
            echo "  WARNING: Expected ${TARGET_WIDTH}x${TARGET_HEIGHT}, got ${w}x${h}"
        fi
    else
        echo "  ERROR: Failed to crop screenshot"
        return 1
    fi
}

# Launch app, wait for window, capture, then kill
launch_capture() {
    local output_path="$1"
    shift
    local extra_args=("$@")

    kill_app

    echo "  Launching: open -a TLingo.app --args ${extra_args[*]}"
    open -a "$APP_PATH" --args "${extra_args[@]}"

    # Wait for the window to actually appear
    if ! wait_for_window; then
        echo "  FAILED: Window never appeared"
        return 1
    fi

    # Extra settle time for UI rendering
    sleep 3

    # For conversation mode, wait longer for the inspector panel
    local is_conversation=false
    for arg in "${extra_args[@]}"; do
        if [ "$arg" = "-SNAPSHOT_CONVERSATION" ]; then
            is_conversation=true
            break
        fi
    done
    if [ "$is_conversation" = true ]; then
        sleep 3
    fi

    capture_screenshot "$output_path"
}

# ==========================================
# Main capture loop
# ==========================================
for locale in "${LOCALES[@]}"; do
    echo "========================================="
    echo "=== Capturing locale: $locale ==="
    echo "========================================="

    output_dir="$OUTPUT_BASE/$locale"
    mkdir -p "$output_dir"

    # Map locale to Apple language code
    case "$locale" in
        "en-US"|"en") LANG_ARGS=("-AppleLanguages" "(en)") ;;
        "zh-Hans")    LANG_ARGS=("-AppleLanguages" "(zh-Hans)") ;;
        "ja")         LANG_ARGS=("-AppleLanguages" "(ja)") ;;
        "ko")         LANG_ARGS=("-AppleLanguages" "(ko)") ;;
        "de")         LANG_ARGS=("-AppleLanguages" "(de)") ;;
        *)
            echo "Unknown locale: $locale"
            continue
            ;;
    esac

    echo ""
    echo "--- 01_Home ($locale) ---"
    launch_capture "$output_dir/01_Home.png" \
        -FASTLANE_SNAPSHOT "${LANG_ARGS[@]}"

    echo ""
    echo "--- 02_Conversation ($locale) ---"
    launch_capture "$output_dir/02_Conversation.png" \
        -FASTLANE_SNAPSHOT -SNAPSHOT_CONVERSATION "${LANG_ARGS[@]}"

    echo ""
    echo "--- 03_Actions ($locale) ---"
    launch_capture "$output_dir/03_Actions.png" \
        -FASTLANE_SNAPSHOT -SNAPSHOT_TAB actions "${LANG_ARGS[@]}"

    echo ""
    echo "--- 04_Models ($locale) ---"
    launch_capture "$output_dir/04_Models.png" \
        -FASTLANE_SNAPSHOT -SNAPSHOT_TAB models "${LANG_ARGS[@]}"

    echo ""
    echo "--- 05_Settings ($locale) ---"
    launch_capture "$output_dir/05_Settings.png" \
        -FASTLANE_SNAPSHOT -SNAPSHOT_TAB settings "${LANG_ARGS[@]}"

    kill_app
    echo ""
    echo "=== Done with locale: $locale ==="
    echo ""
done

echo ""
echo "=== All screenshots captured! ==="
echo ""

# Summary with size and uniqueness verification
for locale in "${LOCALES[@]}"; do
    echo "--- $locale ---"
    for f in "$OUTPUT_BASE/$locale/"*.png; do
        if [ -f "$f" ]; then
            w=$(sips -g pixelWidth "$f" 2>/dev/null | awk '/pixelWidth/ {print $2}')
            h=$(sips -g pixelHeight "$f" 2>/dev/null | awk '/pixelHeight/ {print $2}')
            md5sum=$(md5 -q "$f")
            echo "  $(basename "$f"): ${w}x${h} (md5: ${md5sum:0:8}...)"
        fi
    done
    echo ""
done

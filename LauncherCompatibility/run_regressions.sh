#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
suite=LauncherCompatibility
source_dir="MnM on Mac"
assets=LauncherCompatibilityAssets
renderer=LauncherNativeAssets/MnMLauncherRetina.dylib
scratch=$(mktemp -d /private/tmp/mnm-regressions.XXXXXX)
trap 'rm -r -- "$scratch"' EXIT
export TMPDIR="$scratch/"
export CLANG_MODULE_CACHE_PATH="$scratch/modules"
unset DYLD_INSERT_LIBRARIES WINEPREFIX MNM_GAME_DOCK_PREFIX
unset MNM_LAUNCHER_RETINA_LOCK MNM_WEBVIEW_BRIDGE_SESSION

run_native() {
    local fixture="$1"
    shift
    local name="${fixture%.*}"
    xcrun clang "$suite/$fixture" "$@" -o "$scratch/$name"
    "$scratch/$name"
}

run_swift() {
    local name="$1"
    shift
    xcrun swiftc -DDEBUG -module-cache-path "$scratch/modules" \
        "$@" "$suite/$name.swift" -o "$scratch/$name"
    "$scratch/$name"
}

runtime_sources=(
    "$source_dir/AppStorage.swift"
    "$source_dir/NativePatcherInstaller.swift"
    "$source_dir/WineInstaller.swift"
    "$source_dir/WineRuntime.swift"
    "$source_dir/GameRunState.swift"
    "$source_dir/WineGamePreferences.swift"
)

run_native test_controller_lease.c -Wall -Wextra -Werror
run_native test_launcher_fit.c -Wall -Wextra -Werror
run_native test_loader_address.c -Wall -Wextra -Werror
run_native test_launcher_retina.m -framework Foundation
xcrun clang "$suite/test_launcher_retina_load.m" -framework Foundation -o "$scratch/retina-load"
WINEPREFIX="$scratch/Prefix-Launcher" MNM_LAUNCHER_RETINA_LOCK=1 \
    MNM_WEBVIEW_BRIDGE_SESSION=0123456789abcdef0123456789abcdef \
    DYLD_INSERT_LIBRARIES="$PWD/$renderer" "$scratch/retina-load"

run_swift test_game_exit_guard "$source_dir/GameExitGuard.swift"
run_swift test_launcher_session_lease "$source_dir/LauncherSessionLease.swift"
run_swift test_wine_session_cleanup "$source_dir/WineSessionCleanup.swift" \
    -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors
run_swift test_wine_game_preferences "$source_dir/WineGamePreferences.swift"
MNM_TEST_APPLICATION_SUPPORT="$scratch/AppSupport" run_swift test_migration "${runtime_sources[@]}"
run_swift test_graphics_prefix_repair "${runtime_sources[@]}"
run_swift test_webview_launch_scope "${runtime_sources[@]}" "$source_dir/WindowsPatcherInstaller.swift" "$source_dir/LauncherRendererIntegrity.swift"
run_swift test_update_cleanup "${runtime_sources[@]}" "$source_dir/AppUpdateInstaller.swift"

/usr/bin/codesign --verify --strict "$renderer"
cp "$renderer" "$scratch/resigned-renderer.dylib"
/usr/bin/codesign --force --sign - "$scratch/resigned-renderer.dylib"
xcrun swiftc -module-cache-path "$scratch/modules" "$source_dir/LauncherRendererIntegrity.swift" \
    "$suite/test_renderer_integrity.swift" -o "$scratch/renderer-integrity"
"$scratch/renderer-integrity" "$renderer" "$scratch/resigned-renderer.dylib" "$assets/manifest.json"

python3 - "$assets" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

assets = Path(sys.argv[1])
files = json.loads((assets / "manifest.json").read_text())["files"]
for name in ("MnMWebViewBridge.dll", "MnMWindowsLauncher.exe", "user32.dll", "ole32.dll"):
    if hashlib.sha256((assets / name).read_bytes()).hexdigest() != files[name]:
        raise SystemExit(f"Compatibility asset checksum mismatch: {name}")
print("Compatibility asset checksums passed.")
PY

plutil -lint "MnM on Mac.xcodeproj/project.pbxproj"
printf 'All regression checks passed.\n'

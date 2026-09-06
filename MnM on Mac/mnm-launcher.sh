#!/bin/bash
set -euo pipefail
preferences_dir="${MNM_SUPPORT_DIR:-$HOME/Library/Application Support/MnM on Mac}"
game_path_file="$preferences_dir/game-path.txt"

game_dir() {
    local candidate=''
    if [ -f "$game_path_file" ]; then
        IFS= read -r candidate < "$game_path_file" || true
        if [ -f "$candidate/mnm.exe" ]; then printf '%s' "$candidate"; return; fi
    fi
    candidate="$preferences_dir/Game/mnm"
    if [ -f "$candidate/mnm.exe" ]; then printf '%s' "$candidate"; return; fi
    return 1
}

case "${1:-}" in
    native-path)
        candidate="$preferences_dir/Tools/mnm_patcher_app.app"
        [ -x "$candidate/Contents/MacOS/mnm_launcher" ] || exit 1
        printf '%s' "$candidate"
        ;;
    game-path) game_dir ;;
    install-directory) printf '%s' "$preferences_dir" ;;
    patch-directory)
        if current_game="$(game_dir)" && [ "$(basename "$current_game")" = mnm ]; then
            dirname "$current_game"
        else
            printf '%s' "$preferences_dir/Game"
        fi
        ;;
    remember-game)
        candidate="${2:-}"
        if [ ! -f "$candidate/mnm.exe" ]; then
            printf 'Choose the folder containing mnm.exe.\n' >&2
            exit 1
        fi
        /bin/mkdir -p "$preferences_dir"
        printf '%s\n' "$candidate" > "$game_path_file"
        ;;
    *) printf 'Unknown launcher action.\n' >&2; exit 2 ;;
esac

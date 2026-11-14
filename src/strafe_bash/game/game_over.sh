# game/game_over.sh — GAME OVER 横幅与画面
[[ -n "${_STRAFE_GAME_OVER_SH:-}" ]] && return 0
_STRAFE_GAME_OVER_SH=1
. "$STRAFE_PROJ_DIR/render/ansi.sh"

game_over_banner () {
    cat <<'EOF'
  ____      _      __  __    _____      ___    __     __    _____     ____  
 / ___|    / \    |  \/  |  | ____|    / _ \   \ \   / /   | ____|   |  _ \ 
| |  _    / _ \   | |\/| |  |  _|     | | | |   \ \ / /    |  _|     | |_) |
| |_| |  / ___ \  | |  | |  | |___    | |_| |    \ V /     | |___    |  _ < 
 \____| /_/   \_\ |_|  |_|  |_____|    \___/      \_/      |_____|   |_| \_\
EOF
}

game_over_screen () {
    screen_clear
    game_over_banner
    printf '\n'
    printf 'press Enter to again, Press q to quit\n'
    local key
    while : ; do
        IFS= read -rsn1 key || true
        case "$key" in
            ''|$'\r'|$'\n') return 0 ;;
            q|Q)            return 1 ;;
        esac
    done
}

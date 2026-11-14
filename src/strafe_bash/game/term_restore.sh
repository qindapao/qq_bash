# game/term_restore.sh — 终端恢复（退出/中断时清理）
[[ -n "${_STRAFE_TERM_RESTORE_SH:-}" ]] && return 0
_STRAFE_TERM_RESTORE_SH=1
. "$STRAFE_PROJ_DIR/render/ansi.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"

term_restore () {
    stty sane
    cursor_show
    printf '%s' "$C_RESET"
    screen_clear
}

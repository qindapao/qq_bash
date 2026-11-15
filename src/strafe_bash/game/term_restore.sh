# game/term_restore.sh — 终端恢复（退出/中断时清理）
[[ -n "${_STRAFE_TERM_RESTORE_SH:-}" ]] && return 0
_STRAFE_TERM_RESTORE_SH=1
. "$STRAFE_PROJ_DIR/render/ansi.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"

term_restore () {
    # 无论从哪个退出路径（正常/INT/TERM/提前 return）都关闭鼠标上报，
    # 否则 shell 会把后续动作当成鼠标序列打印出来。
    printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l'
    stty sane
    cursor_show
    printf '%s' "$C_RESET"
    screen_clear
}

# render/ansi.sh — ANSI 控制基础函数
[[ -n "${_STRAFE_ANSI_SH:-}" ]] && return 0
_STRAFE_ANSI_SH=1

ESC=$'\033'
cursor_hide  () { printf '%s[?25l' "$ESC" ; }
cursor_show  () { printf '%s[?25h' "$ESC" ; }
screen_clear () { printf '%s[2J%s[H' "$ESC" "$ESC" ; }
goto         () { printf '%s[%d;%dH' "$ESC" "$1" "$2" ; }
clear_line   () { printf '%s[K' "$ESC" ; }

# 同步输出（DECSET 2026）：把一帧当一次原子提交。终端按脏行重绘，而本游戏每帧
# 都会弄脏几乎所有行，30fps 下中间态可见（闪烁）。不支持的终端会忽略这两个序列。
#
# 一帧唯一的输出点：仍是一次 printf，不增加调用次数，也不多一次 fork。
# 调用方只管往 FRAME_BUF 拼，flush 后清空。
frame_flush () {
    [[ -n "$FRAME_BUF" ]] || return 0
    printf '%s[?2026h%s%s[?2026l' "$ESC" "$FRAME_BUF" "$ESC"
    FRAME_BUF=''
    return 0
}

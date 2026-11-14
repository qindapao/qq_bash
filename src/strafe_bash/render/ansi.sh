# render/ansi.sh — ANSI 控制基础函数
[[ -n "${_STRAFE_ANSI_SH:-}" ]] && return 0
_STRAFE_ANSI_SH=1

ESC=$'\033'
cursor_hide  () { printf '%s[?25l' "$ESC" ; }
cursor_show  () { printf '%s[?25h' "$ESC" ; }
screen_clear () { printf '%s[2J%s[H' "$ESC" "$ESC" ; }
goto         () { printf '%s[%d;%dH' "$ESC" "$1" "$2" ; }
clear_line   () { printf '%s[K' "$ESC" ; }

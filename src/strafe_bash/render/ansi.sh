# render/ansi.sh — ANSI 控制基础函数
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[ansi]++ )) && return 0

# ESC 常量在 config/const.sh（项目级）；这里确保它已加载
. "$STRAFE_PROJ_DIR/config/const.sh"
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

# 备用屏幕：它没有回滚缓冲。mintty 在存在 scrollback 时会把回滚行数算进鼠标
# 行号（飞机被顶到屏幕边缘），备用屏幕下这种偏移不存在；退出时原样还原玩家
# 进入前的画面。只在启动/退出各发一次，不进入帧循环。
alt_screen_enter () { printf '%s[?1049h' "$ESC" ; }
alt_screen_leave () { printf '%s[?1049l' "$ESC" ; }

# game/term_restore.sh — 终端恢复（退出/中断时清理）
[[ -n "${_STRAFE_TERM_RESTORE_SH:-}" ]] && return 0
_STRAFE_TERM_RESTORE_SH=1
. "$STRAFE_PROJ_DIR/render/ansi.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"

term_restore () {
    # INT/TERM/HUP 各自的 trap 会先调一次，退出时 EXIT trap 还会再调一次：
    # 只做一次，避免重复退出备用屏幕、重复清输入。
    [[ -n "${_TERM_RESTORED:-}" ]] && return 0
    _TERM_RESTORED=1

    # 无论从哪个退出路径（正常/INT/TERM/提前 return）都关闭鼠标上报，
    # 否则 shell 会把后续动作当成鼠标序列打印出来。
    # 1000/1002/1003/1006 是我们自己开的；1015/1016/9/1004 是部分终端的像素模式
    # 与焦点上报，一并关掉，避免上一次异常退出残留的模式继续产报文。
    printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l'
    printf '\033[?1015l\033[?1016l\033[?9l\033[?1004l'

    # 丢弃退出瞬间还排在输入队列里的鼠标报文：回到 shell 后终端会 echo 它们，
    # 在提示符后面留下一串 "35;54;41M" 之类的乱码。此刻仍是 raw 模式，读不阻塞。
    local _junk _i
    for (( _i=0 ; _i<64 ; _i++ )) ; do
        IFS= read -r -t 0.01 -n 512 _junk 2>/dev/null || break
        [[ -n "$_junk" ]] || break
    done

    stty sane
    cursor_show
    printf '%s' "$C_RESET"
    # 退出备用屏幕会把玩家进入前的画面原样还回来，所以这里绝不能清屏
    alt_screen_leave
    _term_playback_error_log
}

# 退出备用屏幕之后，把本次运行的错误日志回放到正常屏幕上：
# 备用屏幕一退出，游戏内的报错文本就全丢了，这里补上最后 20 行。
_term_playback_error_log () {
    local _log=${STRAFE_ERRLOG:-}
    [[ -n "$_log" && -s "$_log" ]] || return 0
    printf '\n%s----- strafe_bash error log (%s) -----%s\n' "$C_RED" "$_log" "$C_RESET"
    tail -n 20 "$_log"
    printf '%s-------------------------------------%s\n' "$C_RED" "$C_RESET"
    return 0
}

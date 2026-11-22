# game/main.sh — 游戏主入口（初始化、加载选择、主循环驱动）
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[main]++ )) && return 0

# 静默加载：xo.in 会 source grammar.sh 并打印 bash 特性开关表，那些输出不能进画面
. "$STRAFE_LIB_HOME/xo.sh" >/dev/null 2>&1

. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/render/ansi.sh"
. "$STRAFE_PROJ_DIR/render/fb.sh"
. "$STRAFE_PROJ_DIR/classes/plane/plane.sh"
. "$STRAFE_PROJ_DIR/save/save.sh"
. "$STRAFE_PROJ_DIR/game/init_game.sh"
. "$STRAFE_PROJ_DIR/game/game_over.sh"
. "$STRAFE_PROJ_DIR/game/term_restore.sh"
. "$STRAFE_PROJ_DIR/game/play_game.sh"
. "$STRAFE_PROJ_DIR/game/intro.sh"

# 致命错误：此时画面已在备用屏幕里，直接打印的提示会随备用屏幕一起被还原掉，
# 所以先退出备用屏幕再报错。
fatal () {
    alt_screen_leave
    printf '%s\n' "$*" >&2
    exit 1
}

main () {
    # 先把恢复钩子装上再干别的：xo_init 要跑好几秒，这段时间被打断（Ctrl-C）
    # 也必须能还原终端，否则会留下半初始化状态。
    trap 'term_restore' EXIT
    trap 'term_restore ; exit 130' INT
    trap 'term_restore ; exit 143' TERM
    # 关窗口（HUP）也要还原，否则终端会被留在备用屏幕里
    trap 'term_restore ; exit 129' HUP

    # 错误日志：备用屏幕退出后原画面就没了，stderr 全量落盘，
    # 退出时由 term_restore 在正常屏幕上回放最后几行。
    STRAFE_ERRLOG="${STRAFE_ERRLOG:-${TMPDIR:-/tmp}/strafe_bash.err}"
    : > "$STRAFE_ERRLOG" 2>/dev/null
    exec 2>>"$STRAFE_ERRLOG"

    # 先进备用屏幕：加载进度条画在备用屏幕里，退出时随它一起消失。
    # stderr 已经重定向到日志，所以进度条走 stdout（fd 1）。
    alt_screen_enter
    cursor_hide
    XO_INIT_PROGRESS=1
    XO_INIT_PROGRESS_FD=1

    # 正式启动走快速路径；-d/--debug 或 STRAFE_DEBUG=1 才做注册表反向校验。
    xo_init "${STRAFE_DEBUG:-0}" || fatal 'xo_init failed'

    # 上一次异常退出可能把鼠标上报留在打开状态，进场前先归零一次。
    printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l'

    stty -echo -icanon time 0 min 0

    intro_screen
    local action=$INTRO_ACTION

    if [[ "$action" == "quit" ]] ; then
        return 0
    fi

    if [[ "$action" == "load" ]] ; then
        if ! load_game ; then
            screen_clear
            printf 'LOAD FAILED — starting a new game...\n'
            sleep 1
            [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] && xo_obj_bury OBJ_player
            xo_obj_born_named OBJ_player "${INTRO_PLANE_CLS:-PlaneBee}" || \
                fatal 'PLAYER CREATE FAILED'
            init_game
        fi
    else
        xo_obj_born_named OBJ_player "${INTRO_PLANE_CLS:-PlaneBee}" || \
            fatal 'PLAYER CREATE FAILED'
        init_game
    fi

    screen_clear

    local ret
    for((;;)) ; do
        play_game ; ret=$?
        (( ret != 0 )) && break
        player_death_fx
        game_over_screen || break
        init_game
        screen_clear
    done

    if [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] ; then
        xo_obj_bury OBJ_player 2>/dev/null || true
    fi
}

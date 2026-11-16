# game/main.sh — 游戏主入口（初始化、加载选择、主循环驱动）
[[ -n "${_STRAFE_MAIN_SH:-}" ]] && return 0
_STRAFE_MAIN_SH=1

. "$STRAFE_LIB_HOME/xo.sh" >/dev/null 2>&1

. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/render/ansi.sh"
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
    xo_init || fatal 'xo_init failed'

    trap 'term_restore' EXIT
    trap 'term_restore ; exit 130' INT
    trap 'term_restore ; exit 143' TERM
    # 关窗口（HUP）也要还原，否则终端会被留在备用屏幕里
    trap 'term_restore ; exit 129' HUP

    # 先进备用屏幕再画：intro 也是全屏画面，退出时由 term_restore 原样还原
    alt_screen_enter
    cursor_hide
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
            [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] && xo_obj_kill OBJ_player
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
    while : ; do
        play_game ; ret=$?
        (( ret != 0 )) && break
        player_death_fx
        game_over_screen || break
        init_game
        screen_clear
    done

    if [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] ; then
        xo_obj_kill OBJ_player 2>/dev/null || true
    fi
}

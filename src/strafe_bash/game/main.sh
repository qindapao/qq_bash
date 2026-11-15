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

main () {
    xo_init || { echo "xo_init failed" ; exit 1 ; }

    trap term_restore EXIT
    trap 'term_restore ; exit 130' INT
    trap 'term_restore ; exit 143' TERM

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
            xo_obj_born_named OBJ_player "${INTRO_PLANE_CLS:-PlaneBee}" || {
                echo 'PLAYER CREATE FAILED' ; return 1
            }
            init_game
        fi
    else
        xo_obj_born_named OBJ_player "${INTRO_PLANE_CLS:-PlaneBee}" || {
            echo 'PLAYER CREATE FAILED' ; return 1
        }
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

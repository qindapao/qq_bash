# game/main.sh — 游戏主入口（初始化、加载选择、主循环驱动）
[[ -n "${_STRAFE_MAIN_SH:-}" ]] && return 0
_STRAFE_MAIN_SH=1

. "$STRAFE_LIB_HOME/xo.sh"

_DIR_M="$(dirname "${BASH_SOURCE[0]}")"
. "$_DIR_M/../config/const.sh"
. "$_DIR_M/../config/globals.sh"
. "$_DIR_M/../render/ansi.sh"
. "$_DIR_M/../classes/plane/plane.sh"
. "$_DIR_M/../save/save.sh"
. "$_DIR_M/init_game.sh"
. "$_DIR_M/game_over.sh"
. "$_DIR_M/term_restore.sh"
. "$_DIR_M/play_game.sh"

main () {
    xo_init || { echo "xo_init failed" ; exit 1 ; }

    local skip_init=0
    if [[ -f "$STRAFE_SAVE_FILE" ]] ; then
        screen_clear
        printf 'Save file found: %s\n' "$STRAFE_SAVE_FILE"
        printf 'Press L to load, any other key to start new game: '
        local key
        IFS= read -rsn1 key
        if [[ "$key" == "l" || "$key" == "L" ]] ; then
            if load_game ; then skip_init=1
            else printf '\nload failed, starting new game...\n' ; sleep 1
            fi
        fi
    fi

    if (( !skip_init )) ; then
        xo_obj_born Plane ; PLAYER=$REPLY
        init_game
    fi

    trap term_restore EXIT
    trap 'term_restore ; exit 130' INT
    trap 'term_restore ; exit 143' TERM
    cursor_hide
    stty -echo -icanon time 0 min 0
    screen_clear

    local ret
    while : ; do
        play_game ; ret=$?
        (( ret != 0 )) && break
        game_over_screen || break
        init_game
        screen_clear
    done

    xo_obj_kill "$PLAYER" 2>/dev/null || true
}

# game/intro.sh — 单页静态开场
[[ -n "${_STRAFE_INTRO_SH:-}" ]] && return 0
_STRAFE_INTRO_SH=1
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/config/art.sh"
. "$STRAFE_PROJ_DIR/render/ansi.sh"
. "$STRAFE_PROJ_DIR/render/frame.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss_spinner.sh"

INTRO_ACTION=''

_intro_text () {
    local row=$1 col=$2 color=$3 text=$4
    printf '%s[%d;%dH%s%s%s' "$ESC" "$row" "$col" "$color" "$text" "$C_RESET"
}

_intro_art () {
    local x=$1 y=$2 color=$3 art=$4
    local r=0 line rest=$art
    while [[ -n "$rest" ]] ; do
        line=${rest%%$'\n'*}
        if [[ "$rest" == *$'\n'* ]] ; then rest=${rest#*$'\n'} ; else rest='' ; fi
        printf '%s[%d;%dH%s%s%s' "$ESC" "$((y + r))" "$x" "$color" "$line" "$C_RESET"
        ((r++))
    done
}

_intro_center () {
    local row=$1 color=$2 text=$3
    local col=$(( (SCREEN_W - ${#text}) / 2 + 1 ))
    (( col < 2 )) && col=2
    _intro_text "$row" "$col" "$color" "$text"
}

_intro_draw () {
    local has_save=$1
    screen_clear
    FRAME_BUF=""
    draw_frame
    printf '%s' "$FRAME_BUF"
    FRAME_BUF=""

    # 标题：逐字换色
    local _title='STRAFE_BASH'
    local -a _tc=("$C_CYAN" "$C_BLUE" "$C_CYAN" "$C_MAGENTA" "$C_PURPLE" "$C_MAGENTA" "$C_YELLOW" "$C_RED" "$C_ORANGE" "$C_YELLOW" "$C_CYAN")
    local -i _tw=$(( ${#_title} * 2 - 1 ))
    local -i _tx=$(( (SCREEN_W - _tw) / 2 + 1 ))
    local -i i
    for ((i=0; i<${#_title}; i++)) ; do
        printf '%s[2;%dH%s%s%s' "$ESC" "$((_tx + i * 2))" "${_tc[i]}" "${_title:i:1}" "$C_RESET"
    done
    _intro_center 3 "$C_YELLOW" 'A pure Bash terminal bullet-hell'

    local -i _base=$(( (SCREEN_W - 62) / 2 + 1 ))
    (( _base < 3 )) && _base=3
    local -i _px=$_base _bx=$((_base + 15)) _sx=$((_base + 38))

    _intro_art "$_px" 7 "$C_GREEN" "$PLANE_ART_BASE"
    _intro_text 10 "$_px" "$C_GREEN" 'PLANE'
    _intro_art "$_bx" 6 "$C_RED" "$BOSS_ART_100"
    _intro_text 11 $((_bx + 4)) "$C_RED" 'BOSS'
    _intro_art "$_sx" 6 "$C_PURPLE" "$BOSS_SPINNER_ART_0"
    _intro_text 11 $((_sx + 4)) "$C_PURPLE" 'SPINNER'

    _intro_text 13 4 "$C_BLUE" 'MOVE'
    _intro_text 13 9 "$C_YELLOW" 'W A S D  /  H J K L'
    _intro_text 13 32 "$C_BLUE" 'FIRE'
    _intro_text 13 37 "$C_GREEN" 'AUTO'

    _intro_text 14 4 "$C_BLUE" 'BOMB'
    _intro_text 14 9 "$C_YELLOW" 'collect b, press SPACE'
    _intro_text 14 34 "$C_BLUE" 'PAUSE P'
    _intro_text 14 43 "$C_BLUE" 'QUIT Q'

    _intro_text 15 4 "$C_BLUE" 'SAVE'
    _intro_text 15 9 "$C_YELLOW" 'S (hidden file)'
    _intro_text 15 30 "$C_BLUE" 'LOAD'
    _intro_text 15 35 "$C_YELLOW" 'L'

    _intro_text 16 4 "$C_BLUE" 'DROPS'
    _intro_text 16 10 "$C_YELLOW" 'H +3HP   b BOMB   m MISSILE   L LANE   S SHIELD'
    _intro_text 17 4 "$C_BLUE" 'WEAPONS'
    _intro_text 17 12 "$C_YELLOW" '2 |    3 *    4 @    5 $'

    _intro_text 19 4 "$C_CYAN" 'https://github.com/qindapao/qq_bash'
    _intro_text 20 4 "$C_YELLOW" 'qindapao  ·  northisland2017@gmail.com'
    _intro_text 21 4 "$C_CYAN" 'https://github.com/qindapao  ·  qindapao.com'

    if (( has_save )) ; then
        _intro_center 23 "$C_GREEN" '[ENTER] NEW GAME    [L] LOAD SAVE    [Q] QUIT'
    else
        _intro_center 23 "$C_GREEN" '[ENTER] NEW GAME    [Q] QUIT'
    fi
}

intro_screen () {
    local _has_save=0
    [[ -f "$STRAFE_SAVE_FILE" ]] && _has_save=1
    _intro_draw "$_has_save"

    local key
    while : ; do
        IFS= read -rsn1 key || { INTRO_ACTION=quit ; return 0 ; }
        case "$key" in
            ''|$'\r'|$'\n'|' ') INTRO_ACTION=start ; return 0 ;;
            l|L) (( _has_save )) && { INTRO_ACTION=load ; return 0 ; } ;;
            q|Q) INTRO_ACTION=quit ; return 0 ;;
        esac
    done
}

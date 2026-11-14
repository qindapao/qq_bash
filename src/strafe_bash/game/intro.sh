# game/intro.sh — 单页开场 + 选机
[[ -n "${_STRAFE_INTRO_SH:-}" ]] && return 0
_STRAFE_INTRO_SH=1
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/config/art.sh"
. "$STRAFE_PROJ_DIR/render/ansi.sh"
. "$STRAFE_PROJ_DIR/render/frame.sh"
. "$STRAFE_PROJ_DIR/classes/plane/plane_types.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss_spinner.sh"

INTRO_ACTION=''
INTRO_PLANE=1
INTRO_PLANE_CLS=PlaneBee

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
        printf '%s[%d;%dH%s%s%s%s' "$ESC" "$((y + r))" "$x" "$color" "$C_BOLD" "$line" "$C_RESET"
        ((r++))
    done
}

_intro_center () {
    local row=$1 color=$2 text=$3
    local col=$(( (SCREEN_W - ${#text}) / 2 + 1 ))
    (( col < 2 )) && col=2
    _intro_text "$row" "$col" "$color" "$text"
}

_intro_plane_fields () {
    local n=$1
    case "$n" in
        2) _icls=PlaneHornet ; _iname='[2] HORNET' ; _iart="$PLANE_ART_HORNET" ; _istat='HP 30  SCORE 60%' ; _idesc='ARMORED' ;;
        3) _icls=PlaneEagle  ; _iname='[3] EAGLE-1' ; _iart="$PLANE_ART_EAGLE"  ; _istat='HP 15  SPD +1' ; _idesc='LASER NO BOOST' ;;
        4) _icls=PlaneIl2    ; _iname='[4] IL-2' ; _iart="$PLANE_ART_IL2" ; _istat='HP 40  SPD -1' ; _idesc='HEAVY ARMOR' ;;
        *) _icls=PlaneBee    ; _iname='[1] BEE' ; _iart="$PLANE_ART_BASE" ; _istat='HP 20  BALANCED' ; _idesc='NO PENALTY' ;;
    esac
}

_intro_plane_card () {
    local n=$1 x=$2 selected=$3
    local -i center=$(( x + 8 ))
    local -i ax
    _intro_plane_fields "$n"
    if (( n == 1 )) ; then ax=$(( center - 1 )) ; else ax=$(( center - 2 )) ; fi

    if (( selected )) ; then
        _intro_text 5 "$x" "$C_REVERSE" "$_iname"
        _intro_text 10 "$center" "$C_GREEN" '^'
    else
        _intro_text 5 "$x" "$C_CYAN" "$_iname"
    fi
    _intro_art "$ax" 6 "$C_BLUE" "$_iart"
    _intro_text 8 "$x" "$C_YELLOW" "$_istat"
    _intro_text 9 "$x" "$C_RESET" "$_idesc"
}

_intro_draw () {
    local has_save=$1 selected=$2
    screen_clear
    FRAME_BUF=""
    draw_frame
    printf '%s' "$FRAME_BUF"
    FRAME_BUF=""

    local _title='STRAFE_BASH'
    local -a _tc=("$C_CYAN" "$C_BLUE" "$C_CYAN" "$C_MAGENTA" "$C_PURPLE" "$C_MAGENTA" "$C_YELLOW" "$C_RED" "$C_ORANGE" "$C_YELLOW" "$C_CYAN")
    local -i _tw=$(( ${#_title} * 2 - 1 ))
    local -i _tx=$(( (SCREEN_W - _tw) / 2 + 1 ))
    local -i i
    for ((i=0; i<${#_title}; i++)) ; do
        printf '%s[2;%dH%s%s%s' "$ESC" "$((_tx + i * 2))" "${_tc[i]}" "${_title:i:1}" "$C_RESET"
    done
    _intro_center 3 "$C_YELLOW" 'A pure Bash terminal bullet-hell'

    local -a _cx=(3 21 39 57)
    for i in 1 2 3 4 ; do
        _intro_plane_card "$i" "${_cx[i-1]}" "$(( i == selected ))"
    done

    _intro_text 12 4 "$C_BLUE" 'MOVE'
    _intro_text 12 9 "$C_YELLOW" 'W A S D  /  H J K L'
    _intro_text 12 30 "$C_BLUE" 'FIRE'
    _intro_text 12 35 "$C_GREEN" 'AUTO'
    _intro_text 12 43 "$C_BLUE" 'DIAG'
    _intro_text 12 48 "$C_YELLOW" 'Y:UL U:UR B:DL N:DR'

    _intro_text 13 4 "$C_BLUE" 'BOMB'
    _intro_text 13 9 "$C_YELLOW" 'collect b + SPACE'
    _intro_text 13 30 "$C_BLUE" 'PAUSE P'
    _intro_text 13 39 "$C_BLUE" 'QUIT Q'

    _intro_text 14 4 "$C_BLUE" 'SAVE'
    _intro_text 14 9 "$C_YELLOW" 'S (hidden file)'
    _intro_text 14 30 "$C_BLUE" 'LOAD'
    _intro_text 14 35 "$C_YELLOW" 'L'
    _intro_text 14 40 "$C_BLUE" 'MOUSE ON'
    _intro_text 14 50 "$C_BLUE" 'RMB BOMB'

    _intro_text 15 4 "$C_BLUE" 'DROPS'
    _intro_text 15 10 "$C_YELLOW" 'H +3HP   b BOMB   m MISSILE   L LANE   S SHIELD'
    _intro_text 16 4 "$C_BLUE" 'WEAPONS'
    _intro_text 16 12 "$C_YELLOW" '2 |    3 #    4 @    5 $'

    _intro_text 19 4 "$C_CYAN" 'https://github.com/qindapao/qq_bash'
    _intro_text 20 4 "$C_YELLOW" 'qindapao  ·  northisland2017@gmail.com'
    _intro_text 21 4 "$C_CYAN" 'https://github.com/qindapao  ·  qindapao.com'

    if (( has_save )) ; then
        _intro_center 23 "$C_GREEN" '1-4 SELECT   ENTER START   L LOAD   Q QUIT'
    else
        _intro_center 23 "$C_GREEN" '1-4 SELECT   ENTER START   Q QUIT'
    fi
}

intro_screen () {
    local _has_save=0
    [[ -f "$STRAFE_SAVE_FILE" ]] && _has_save=1
    INTRO_PLANE=1
    INTRO_PLANE_CLS=PlaneBee

    local key
    while : ; do
        _intro_draw "$_has_save" "$INTRO_PLANE"
        IFS= read -rsn1 key || { INTRO_ACTION=quit ; return 0 ; }
        case "$key" in
            1|2|3|4)
                INTRO_PLANE=$key
                _intro_plane_fields "$INTRO_PLANE"
                INTRO_PLANE_CLS=$_icls
                continue
                ;;
            ''|$'\r'|$'\n'|' ') INTRO_ACTION=start ; return 0 ;;
            l|L) (( _has_save )) && { INTRO_ACTION=load ; return 0 ; } ;;
            q|Q) INTRO_ACTION=quit ; return 0 ;;
        esac
    done
}

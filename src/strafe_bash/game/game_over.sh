# game/game_over.sh — 死亡爆炸、GAME OVER 与结算
[[ -n "${_STRAFE_GAME_OVER_SH:-}" ]] && return 0
_STRAFE_GAME_OVER_SH=1
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/render/ansi.sh"

player_death_fx () {
    [[ -n "$PLAYER" && -n "${XO_OBJ_POOL[$PLAYER]+_}" ]] || return 0
    local -n p=$PLAYER
    local -i x=${p["{x}$X"]} y=${p["{y}$X"]}
    unset -n p

    local -a _dx=(0 1 1 1 0 -1 -1 -1)
    local -a _dy=(-1 -1 0 1 1 1 0 -1)
    local -a _chars=('*' '@' '#' '+' '.')
    local -a _colors=("$C_RED" "$C_YELLOW" "$C_ORANGE" "$C_MAGENTA")
    local -a _old=()
    local -i i f nx ny r ci

    # 先把飞机本体擦掉
    for ((i=-1; i<=1; i++)) ; do
        goto "$y" "$((x + i))" ; printf ' '
        goto "$((y + 1))" "$((x + i))" ; printf ' '
    done

    # 中心闪白，再向外扩散
    goto "$y" "$x" ; printf '%s@%s' "$C_YELLOW" "$C_RESET"
    sleep 0.10
    for ((f=0; f<10; f++)) ; do
        for ((i=0; i<${#_old[@]}; i+=2)) ; do
            goto "${_old[i]}" "${_old[i+1]}" ; printf ' '
        done
        _old=()
        r=$(( f / 2 + 1 ))
        for ((i=0; i<8; i++)) ; do
            nx=$(( x + _dx[i] * r ))
            ny=$(( y + _dy[i] * r ))
            (( nx < 2 )) && nx=2
            (( nx > SCREEN_W - 2 )) && nx=$(( SCREEN_W - 2 ))
            (( ny < 2 )) && ny=2
            (( ny > SCREEN_H - 1 )) && ny=$(( SCREEN_H - 1 ))
            ci=$(( RANDOM % ${#_colors[@]} ))
            goto "$ny" "$nx"
            printf '%s%s%s' "${_colors[ci]}" "${_chars[RANDOM % ${#_chars[@]}]}" "$C_RESET"
            _old+=("$ny" "$nx")
        done
        sleep 0.045
    done
    for ((i=0; i<${#_old[@]}; i+=2)) ; do
        goto "${_old[i]}" "${_old[i+1]}" ; printf ' '
    done
    goto "$y" "$x" ; printf ' '
}

game_over_banner () {
    cat <<'EOF'
  ____      _      __  __    _____      ___    __     __    _____     ____
 / ___|    / \    |  \/  |  | ____|    / _ \   \ \   / /   | ____|   |  _ \
| |  _    / _ \   | |\/| |  |  _|     | | | |   \ \ / /    |  _|     | |_) |
| |_| |  / ___ \  | |  | |  | |___    | |_| |    \ V /     | |___    |  _ <
 \____| /_/   \_\ |_|  |_|  |_____|    \___/      \_/      |_____|   |_| \_\
EOF
}

game_over_screen () {
    local -i score=0 secs mm ss
    if [[ -n "$PLAYER" && -n "${XO_OBJ_POOL[$PLAYER]+_}" ]] ; then
        local -n p=$PLAYER
        score=${p["{score}$X"]:-0}
        unset -n p
    fi
    secs=$(( G_RUN_TICKS / FPS ))
    mm=$(( secs / 60 ))
    ss=$(( secs % 60 ))

    screen_clear
    printf '%s' "$C_RED"
    game_over_banner
    printf '%s' "$C_RESET"

    local -i col=$(( (SCREEN_W - 34) / 2 + 1 ))
    (( col < 2 )) && col=2
    goto 9 "$col"
    printf '%sFINAL SCORE%s  %s%d%s' "$C_CYAN" "$C_RESET" "$C_YELLOW" "$score" "$C_RESET"
    goto 10 "$col"
    printf '%sTIME%s         %s%02d:%02d%s' "$C_CYAN" "$C_RESET" "$C_YELLOW" "$mm" "$ss" "$C_RESET"
    goto 11 "$col"
    printf '%sKILLS%s        %s%d%s' "$C_CYAN" "$C_RESET" "$C_YELLOW" "$G_KILLS" "$C_RESET"
    goto 12 "$col"
    printf '%sBOSS KILLS%s   %s%d%s' "$C_CYAN" "$C_RESET" "$C_YELLOW" "$G_BOSS_KILLS" "$C_RESET"

    local _prompt='[ENTER] RETRY    [Q] QUIT'
    col=$(( (SCREEN_W - ${#_prompt}) / 2 + 1 ))
    (( col < 2 )) && col=2
    goto 16 "$col"
    printf '%s%s%s' "$C_GREEN" "$_prompt" "$C_RESET"

    local key
    while : ; do
        IFS= read -rsn1 key || return 1
        case "$key" in
            ''|$'\r'|$'\n') return 0 ;;
            q|Q) return 1 ;;
        esac
    done
}

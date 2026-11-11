#!/usr/bin/env bash
# STRAFE_BASH — horizontal terminal shooter built on x.sh + xo.sh

: "${STRAFE_LIB_HOME:=../bashlib}"
. "$STRAFE_LIB_HOME/xo.sh"

# ===== ANSI 控制 =====
ESC=$'\033'
cursor_hide  () { printf '%s[?25l' "$ESC" ; }
cursor_show  () { printf '%s[?25h' "$ESC" ; }
screen_clear () { printf '%s[2J%s[H' "$ESC" "$ESC" ; }
goto         () { printf '%s[%d;%dH' "$ESC" "$1" "$2" ; }
clear_line   () { printf '%s[K' "$ESC" ; }

# ===== 类：Plane =====
readonly PlaneStaticTemplate='
    PlaneObj ->
        {CLS} => Plane
        {SUP} => Base
        {MIX} => 
    '
Plane_born () {
    local -n self=$1
    self["{x}$X"]=5
    self["{y}$X"]=$(( SCREEN_H / 2 ))
    self["{hp}$X"]=3
    self["{score}$X"]=0
    self["{symbol}$X"]='>'
}
Plane_move () {
    local -n self=$1
    goto "${self["{y}$X"]}" "${self["{x}$X"]}" ; printf ' '
    local y=$(( ${self["{y}$X"]} + $2 ))
    (( y < 2 )) && y=2
    (( y > SCREEN_H - 2 )) && y=$(( SCREEN_H - 2 ))
    self["{y}$X"]=$y
}
Plane_fire () {
    local -n self=$1
    xo_obj_born Bullet $(( ${self["{x}$X"]} + 1 )) "${self["{y}$X"]}"
    BULLETS+=("$REPLY")
}

# ===== 类：Bullet =====
readonly BulletStaticTemplate='
    BulletObj ->
        {CLS} => Bullet
        {SUP} => Base
        {MIX} => 
    '
Bullet_born () {
    local -n self=$1
    self["{x}$X"]=$2
    self["{y}$X"]=$3
    self["{symbol}$X"]='-'
}
Bullet_move () {
    local -n self=$1
    goto "${self["{y}$X"]}" "${self["{x}$X"]}" ; printf ' '
    self["{x}$X"]=$(( ${self["{x}$X"]} + 1 ))
}

# ===== 类：Enemy =====
readonly EnemyStaticTemplate='
    EnemyObj ->
        {CLS} => Enemy
        {SUP} => Base
        {MIX} => 
    '
Enemy_born () {
    local -n self=$1
    self["{x}$X"]=$(( SCREEN_W - 2 ))
    self["{y}$X"]=$(( (RANDOM % (SCREEN_H - 4)) + 2 ))
    self["{symbol}$X"]='<'
    self["{hp}$X"]=1
}
Enemy_move () {
    local -n self=$1
    goto "${self["{y}$X"]}" "${self["{x}$X"]}" ; printf ' '
    self["{x}$X"]=$(( ${self["{x}$X"]} - 1 ))
}

# ===== 全局状态 =====
SCREEN_W=$(tput cols)  ; (( SCREEN_W > 80 )) && SCREEN_W=80
SCREEN_H=$(tput lines) ; (( SCREEN_H > 24 )) && SCREEN_H=24
declare -a BULLETS=() ENEMIES=()
declare PLAYER=

render () {
    local -n p=$PLAYER
    # 刷新状态栏
    goto 1 1 ; clear_line
    printf 'HP:%d  SCORE:%d' "${p["{hp}$X"]}" "${p["{score}$X"]}"
    
    # 重绘飞机
    goto "${p["{y}$X"]}" "${p["{x}$X"]}" ; printf '%s' "${p["{symbol}$X"]}"
    unset -n p
    
    local b e
    for b in "${BULLETS[@]}" ; do
        local -n _b=$b
        goto "${_b["{y}$X"]}" "${_b["{x}$X"]}" ; printf '%s' "${_b["{symbol}$X"]}"
        unset -n _b
    done
    for e in "${ENEMIES[@]}" ; do
        local -n _e=$e
        goto "${_e["{y}$X"]}" "${_e["{x}$X"]}" ; printf '%s' "${_e["{symbol}$X"]}"
        unset -n _e
    done
}

term_restore () {
    stty sane
    cursor_show
    screen_clear
}

main () {
    xo_init || { echo "xo_init failed" ; exit 1 ; }
    xo_obj_born Plane ; PLAYER=$REPLY

    trap term_restore EXIT INT TERM
    cursor_hide
    stty -echo -icanon time 0 min 0
    
    # 游戏启动清屏
    screen_clear

    local tick=0 key b e fire_cd=0

    while : ; do
        # 开火冷却控制
        ((fire_cd > 0)) && ((fire_cd--))

        key=
        # 防止 read 吞掉空格键
        IFS= read -rsn1 -t 0.02 key || true
        
        case "$key" in
            w|k) xo_call "$PLAYER" move -1 ;;
            s|j) xo_call "$PLAYER" move  1 ;;
            ' ') 
                # 限制连射速度，防止子弹太多卡顿
                if (( fire_cd == 0 )); then
                    xo_call "$PLAYER" fire 
                    fire_cd=6
                fi
                ;;
            q)   break ;;
        esac

        # 子弹前进 + 出界回收
        local -a alive_b=()
        for b in "${BULLETS[@]}" ; do
            xo_call "$b" move
            local -n _b=$b
            if (( ${_b["{x}$X"]} >= SCREEN_W - 1 )) ; then
                goto "${_b["{y}$X"]}" "${_b["{x}$X"]}" ; printf ' '
                xo_obj_kill "$b"
            else
                alive_b+=("$b")
            fi
            unset -n _b
        done
        BULLETS=("${alive_b[@]}")

        # 敌人前进 + 出界回收
        local -a alive_e=()
        for e in "${ENEMIES[@]}" ; do
            xo_call "$e" move
            local -n _e=$e
            if (( ${_e["{x}$X"]} <= 1 )) ; then
                goto "${_e["{y}$X"]}" "${_e["{x}$X"]}" ; printf ' '
                xo_obj_kill "$e"
            else
                alive_e+=("$e")
            fi
            unset -n _e
        done
        ENEMIES=("${alive_e[@]}")

        # 碰撞检测
        local -a hit_b=() hit_e=()
        for b in "${BULLETS[@]}" ; do
            local -n _b=$b
            local bx=${_b["{x}$X"]} by=${_b["{y}$X"]}
            unset -n _b
            for e in "${ENEMIES[@]}" ; do
                local -n _e=$e
                # 【修复量子隧穿】子弹向右，敌机向左，只要 bx >= ex 即命中！
                if (( bx >= ${_e["{x}$X"]} && by == ${_e["{y}$X"]} )) ; then
                    hit_b+=("$b") ; hit_e+=("$e")
                    unset -n _e
                    break
                fi
                unset -n _e
            done
        done

        if ((${#hit_b[@]})) ; then
            for b in "${hit_b[@]}" ; do 
                local -n _b=$b
                goto "${_b["{y}$X"]}" "${_b["{x}$X"]}" ; printf ' '
                unset -n _b
                xo_obj_kill "$b" 
            done
            for e in "${hit_e[@]}" ; do 
                local -n _e=$e
                goto "${_e["{y}$X"]}" "${_e["{x}$X"]}" ; printf ' '
                unset -n _e
                xo_obj_kill "$e" 
            done
            
            local -n p=$PLAYER
            p["{score}$X"]=$(( ${p["{score}$X"]} + 10 * ${#hit_e[@]} ))
            unset -n p

            local -A dead_b=() dead_e=()
            for b in "${hit_b[@]}" ; do dead_b[$b]=1 ; done
            for e in "${hit_e[@]}" ; do dead_e[$e]=1 ; done
            
            local -a nb=() ne=()
            for b in "${BULLETS[@]}" ; do 
                [[ -n "${dead_b[$b]+_}" ]] || nb+=("$b")
            done
            for e in "${ENEMIES[@]}" ; do 
                [[ -n "${dead_e[$e]+_}" ]] || ne+=("$e")
            done
            BULLETS=("${nb[@]}") ; ENEMIES=("${ne[@]}")
        fi

        # 刷怪
        (( tick++ % 10 == 0 )) && { xo_obj_born Enemy ; ENEMIES+=("$REPLY") ; }

        render
    done

    xo_obj_kill "$PLAYER"
}

main

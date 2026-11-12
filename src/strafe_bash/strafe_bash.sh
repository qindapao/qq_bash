#!/usr/bin/env bash
# STRAFE_BASH — vertical terminal shooter built on x.sh + xo.sh

: "${STRAFE_LIB_HOME:=../bashlib}"
. "$STRAFE_LIB_HOME/xo.sh"

# ===== ANSI =====
ESC=$'\033'
cursor_hide  () { printf '%s[?25l' "$ESC" ; }
cursor_show  () { printf '%s[?25h' "$ESC" ; }
screen_clear () { printf '%s[2J%s[H' "$ESC" "$ESC" ; }
goto         () { printf '%s[%d;%dH' "$ESC" "$1" "$2" ; }
clear_line   () { printf '%s[K' "$ESC" ; }

# ===== 颜色 =====
C_RESET=$'\033[0m'
C_BLUE=$'\033[38;5;33m'
C_RED=$'\033[38;5;196m'
C_ORANGE=$'\033[38;5;208m'
C_YELLOW=$'\033[38;5;226m'
C_GREEN=$'\033[38;5;46m'
C_PURPLE=$'\033[38;5;129m'
C_MAGENTA=$'\033[38;5;201m'

# ===== 全局 =====
SCREEN_W=$(tput cols 2>/dev/null)  ; [[ -z "$SCREEN_W" ]] && SCREEN_W=80
(( SCREEN_W > 120 )) && SCREEN_W=120
SCREEN_H=$(tput lines 2>/dev/null) ; [[ -z "$SCREEN_H" ]] && SCREEN_H=24
(( SCREEN_H > 40 )) && SCREEN_H=40
STRAFE_SAVE_FILE="${STRAFE_SAVE_FILE:-./.strafe_save}"
GAME_TOP=4
FPS=50

BONUS_T2=$(( 60 * FPS ))
BONUS_T3=$(( 50 * FPS ))
BONUS_T4=$(( 40 * FPS ))
BONUS_T5=$(( 30 * FPS ))
BONUS_MT=$(( 30 * FPS ))

declare -a BULLETS=() ENEMIES=() DROPS=() ENEMY_BULLETS=() MISSILES=()
declare -a BOMB_FX_POS=()
declare -a BOSS_FX_POS=()
declare BOSS_FX_CX=0 BOSS_FX_CY=0
declare PLAYER=

BOSS_ART_100=$'    _____    \n   /     \\   \n  /  O O  \\  \n  \\_|_|_|_/  \n   \\_____/   '
BOSS_ART_70=$'    _____    \n   /     \\   \n  /  O O  \\  \n  \\_|_|_/    \n   \\_____/   '
BOSS_ART_50=$'    _____    \n   /     \\   \n  /  O O  \\  \n  \\_|_/      \n   \\_____/   '
BOSS_ART_20=$'    _____    \n   /     \\   \n  /  O O  \\  \n  \\_______/  \n   \\_____/   '

# ===== BulletType =====
readonly BulletTypeStaticTemplate='
    BulletTypeObj ->
        {CLS} => BulletType
        {SUP} => Base
        {MIX} => 
        {symbol} => .
        {damage} => 1
    '
BulletType_born () {
    local -n self=$1
    [[ -n "$2" ]] && self["{symbol}$X"]=$2
    [[ -n "$3" ]] && self["{damage}$X"]=$3
}

# ===== Bullet =====
readonly BulletStaticTemplate='
    BulletObj ->
        {CLS} => Bullet
        {SUP} => Base
        {MIX} => 
        {x} => 0
        {y} => 0
        {symbol} => .
        {damage} => 1
    '
Bullet_born () {
    local -n self=$1
    self["{x}$X"]=$2
    self["{y}$X"]=$3
    self["{symbol}$X"]=$4
    self["{damage}$X"]=$5
}
Bullet_move () {
    local -n self=$1
    printf '\033[%d;%dH ' "${self["{y}$X"]}" "${self["{x}$X"]}"
    self["{y}$X"]=$(( ${self["{y}$X"]} - 1 ))
}

# ===== Missile（横向分量加强，撞边消失） =====
readonly MissileStaticTemplate='
    MissileObj ->
        {CLS} => Missile
        {SUP} => Base
        {MIX} => 
        {x} => 0
        {y} => 0
        {symbol} => ^
        {damage} => 2
        {vx} => 0
        {vy} => -1
    '
Missile_born () {
    local -n self=$1
    self["{x}$X"]=$2
    self["{y}$X"]=$3
    self["{damage}$X"]=${4:-2}
    self["{vx}$X"]=0
    self["{vy}$X"]=-1
    self["{symbol}$X"]='^'
}
Missile_move () {
    local -n self=$1
    local _x=${self["{x}$X"]} _y=${self["{y}$X"]}
    printf '\033[%d;%dH ' "$_y" "$_x"

    # 40% 概率转向：上 50% / 左 25% / 右 25%
    if (( RANDOM % 10 < 4 )) ; then
        local _r=$(( RANDOM % 20 ))
        if (( _r < 10 )) ; then
            self["{vx}$X"]=0 ; self["{vy}$X"]=-1
        elif (( _r < 15 )) ; then
            self["{vx}$X"]=-1 ; self["{vy}$X"]=0
        else
            self["{vx}$X"]=1 ; self["{vy}$X"]=0
        fi
    fi

    _x=$(( _x + ${self["{vx}$X"]} ))
    _y=$(( _y + ${self["{vy}$X"]} ))
    self["{x}$X"]=$_x
    self["{y}$X"]=$_y

    local _vx=${self["{vx}$X"]} _vy=${self["{vy}$X"]}
    if (( _vy < 0 )) ; then self["{symbol}$X"]='^'
    elif (( _vy > 0 )) ; then self["{symbol}$X"]='v'
    elif (( _vx < 0 )) ; then self["{symbol}$X"]='<'
    elif (( _vx > 0 )) ; then self["{symbol}$X"]='>'
    fi

    # 撞左右上边界消失
    (( _x < 2 )) && return 1
    (( _x > SCREEN_W - 2 )) && return 1
    (( _y < GAME_TOP )) && return 1
    (( _y >= SCREEN_H - 1 )) && return 1
    return 0
}

# ===== EnemyBullet =====
readonly EnemyBulletStaticTemplate='
    EnemyBulletObj ->
        {CLS} => EnemyBullet
        {SUP} => Base
        {MIX} => 
        {x} => 0
        {y} => 0
        {symbol} => .
        {damage} => 1
        {cd} => 0
    '
EnemyBullet_born () {
    local -n self=$1
    self["{x}$X"]=$2
    self["{y}$X"]=$3
    self["{symbol}$X"]=$4
    self["{damage}$X"]=$5
    self["{cd}$X"]=0
}
EnemyBullet_move () {
    local -n self=$1
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    (( cd < 4 )) && { self["{cd}$X"]=$cd ; return 0 ; }
    self["{cd}$X"]=0
    printf '\033[%d;%dH ' "${self["{y}$X"]}" "${self["{x}$X"]}"
    self["{y}$X"]=$(( ${self["{y}$X"]} + 1 ))
    (( ${self["{y}$X"]} >= SCREEN_H - 1 )) && return 1
    return 0
}

# ===== Plane =====
readonly PlaneStaticTemplate='
    PlaneObj ->
        {CLS} => Plane
        {SUP} => Base
        {MIX} => 
        {x} => 0
        {y} => 0
        {w} => 3
        {h} => 2
        {art} => 
        {hp} => 20
        {score} => 0
        {symbol} => ^
        {bullet} => 
        {bombs} => 0
        {t2} => 0
        {t3} => 0
        {t4} => 0
        {t5} => 0
        {mt} => 0
    '
Plane_born () {
    local -n self=$1
    self["{x}$X"]=$(( SCREEN_W / 2 ))
    self["{y}$X"]=$(( SCREEN_H - 2 ))
    self["{art}$X"]="o|o"$'\n'"-'-"
}
Plane_kill () {
    local -n self=$1
    local bt=${self["{bullet}$X"]}
    [[ -n "$bt" && -n "${XO_OBJ_POOL[$bt]+_}" ]] && xo_obj_kill "$bt"
}
Plane_move () {
    local -n self=$1
    local dx=${2:-0} dy=${3:-0}
    _art_clear_at ${self["{y}$X"]} $(( ${self["{x}$X"]} - 1 )) "${self["{art}$X"]}"
    local x=$(( ${self["{x}$X"]} + dx ))
    local y=$(( ${self["{y}$X"]} + dy ))
    (( x < 2 )) && x=2
    (( x > SCREEN_W - 2 )) && x=$(( SCREEN_W - 2 ))
    (( y < GAME_TOP )) && y=$GAME_TOP
    (( y > SCREEN_H - 2 )) && y=$(( SCREEN_H - 2 ))
    self["{x}$X"]=$x
    self["{y}$X"]=$y
}
Plane_fire () {
    local -n self=$1
    local bt=${self["{bullet}$X"]}
    local -n bt_obj=$bt
    local sym=${bt_obj["{symbol}$X"]}
    local dmg=${bt_obj["{damage}$X"]}
    unset -n bt_obj
    xo_obj_born Bullet "${self["{x}$X"]}" $(( ${self["{y}$X"]} - 1 )) "$sym" "$dmg"
    BULLETS+=("$REPLY")
}

_art_clear_at () {
    local ay=$1 ax=$2 art=$3
    local r=0 line rest=$art
    while [[ -n "$rest" ]] ; do
        line=${rest%%$'\n'*}
        if [[ "$rest" == *$'\n'* ]] ; then
            rest=${rest#*$'\n'}
        else
            rest=''
        fi
        printf '\033[%d;%dH%*s' $((ay + r)) "$ax" "${#line}" ''
        ((r++))
    done
}

# ===== Enemy 基类 =====
readonly EnemyStaticTemplate='
    EnemyObj ->
        {CLS} => Enemy
        {SUP} => Base
        {MIX} => 
        {x} => 0
        {y} => 0
        {symbol} => 
        {hp} => 1
        {maxhp} => 1
        {score} => 0
        {cd} => 0
        {vx} => 0
        {vy} => 1
        {w} => 1
        {h} => 1
        {art} => 
    '
Enemy_born () {
    local -n self=$1
    local w=${self["{w}$X"]:-1}
    (( w < 1 )) && w=1
    self["{x}$X"]=$(( RANDOM % (SCREEN_W - 2 - w) + 2 ))
    self["{y}$X"]=$GAME_TOP
    self["{vx}$X"]=0
    self["{vy}$X"]=1
    self["{cd}$X"]=0
}

_enemy_fire () {
    local e=$1 percent=$2 esym=$3 edmg=$4
    (( RANDOM % 100 < percent )) || return 0
    local -n _e=$e
    local _fw=${_e["{w}$X"]}
    local _fy=$(( ${_e["{y}$X"]} + ${_e["{h}$X"]} ))
    local _fx=$(( ${_e["{x}$X"]} + _fw / 2 ))
    xo_obj_born EnemyBullet "$_fx" "$_fy" "$esym" "$edmg"
    ENEMY_BULLETS+=("$REPLY")
    unset -n _e
}

# ---- EnemyV ----
readonly EnemyVStaticTemplate='
    EnemyVObj ->
        {CLS} => EnemyV
        {SUP} => Enemy
        {MIX} => 
        {symbol} => v
        {hp} => 1
        {maxhp} => 1
        {score} => 10
        {w} => 3
        {h} => 2
    '
EnemyV_born () {
    local -n self=$1
    Enemy_born "$1"
    self["{art}$X"]=$' v \n/ \\'
}
EnemyV_move () {
    local -n self=$1
    _enemy_fire "$1" 2 '.' 1
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    (( cd < 6 )) && { self["{cd}$X"]=$cd ; return 0 ; }
    self["{cd}$X"]=0
    local _ay=${self["{y}$X"]} _ax=${self["{x}$X"]} _w=${self["{w}$X"]} _h=${self["{h}$X"]}
    _art_clear_at "$_ay" "$_ax" "${self["{art}$X"]}"
    (( RANDOM % 3 == 0 )) && {
        local dx=$(( (RANDOM % 2) * 2 - 1 ))
        local x=$(( _ax + dx ))
        (( x < 2 )) && x=2
        (( x > SCREEN_W - 2 - _w )) && x=$(( SCREEN_W - 2 - _w ))
        self["{x}$X"]=$x
    }
    self["{y}$X"]=$(( _ay + 1 ))
    (( ${self["{y}$X"]} + _h > SCREEN_H - 1 )) && return 1
    return 0
}

# ---- EnemyQ ----
readonly EnemyQStaticTemplate='
    EnemyQObj ->
        {CLS} => EnemyQ
        {SUP} => Enemy
        {MIX} => 
        {symbol} => Q
        {hp} => 5
        {maxhp} => 5
        {score} => 30
        {w} => 3
        {h} => 2
    '
EnemyQ_born () {
    local -n self=$1
    Enemy_born "$1"
    self["{art}$X"]=$' Q \n[_]'
}
EnemyQ_move () {
    local -n self=$1
    _enemy_fire "$1" 3 '.' 1
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    (( cd < 10 )) && { self["{cd}$X"]=$cd ; return 0 ; }
    self["{cd}$X"]=0
    local _ay=${self["{y}$X"]} _ax=${self["{x}$X"]} _w=${self["{w}$X"]} _h=${self["{h}$X"]}
    _art_clear_at "$_ay" "$_ax" "${self["{art}$X"]}"
    (( RANDOM % 3 == 0 )) && {
        local dx=$(( (RANDOM % 2) * 2 - 1 ))
        local x=$(( _ax + dx ))
        (( x < 2 )) && x=2
        (( x > SCREEN_W - 2 - _w )) && x=$(( SCREEN_W - 2 - _w ))
        self["{x}$X"]=$x
    }
    self["{y}$X"]=$(( _ay + 1 ))
    (( ${self["{y}$X"]} + _h > SCREEN_H - 1 )) && return 1
    return 0
}

# ---- EnemyM ----
readonly EnemyMStaticTemplate='
    EnemyMObj ->
        {CLS} => EnemyM
        {SUP} => Enemy
        {MIX} => 
        {symbol} => M
        {hp} => 10
        {maxhp} => 10
        {score} => 100
        {w} => 5
        {h} => 3
    '
EnemyM_born () {
    local -n self=$1
    Enemy_born "$1"
    self["{art}$X"]=$' ___ \n| M |\n|___|'
}
EnemyM_move () {
    local -n self=$1
    _enemy_fire "$1" 4 '+' 3
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    (( cd < 14 )) && { self["{cd}$X"]=$cd ; return 0 ; }
    self["{cd}$X"]=0
    local _ay=${self["{y}$X"]} _ax=${self["{x}$X"]} _w=${self["{w}$X"]} _h=${self["{h}$X"]}
    _art_clear_at "$_ay" "$_ax" "${self["{art}$X"]}"
    (( _ay + _h < SCREEN_H )) && { printf '\033[%d;%dH%*s' $((_ay + _h)) "$_ax" 15 '' ; }
    (( RANDOM % 3 == 0 )) && {
        local dx=$(( (RANDOM % 2) * 2 - 1 ))
        local x=$(( _ax + dx ))
        (( x < 2 )) && x=2
        (( x > SCREEN_W - 2 - _w )) && x=$(( SCREEN_W - 2 - _w ))
        self["{x}$X"]=$x
    }
    local vy=${self["{vy}$X"]}
    (( RANDOM % 7 == 0 )) && vy=$(( -vy ))
    self["{vy}$X"]=$vy
    local y=$(( _ay + vy ))
    (( y < GAME_TOP )) && { y=$GAME_TOP ; self["{vy}$X"]=1 ; }
    self["{y}$X"]=$y
    (( y + _h > SCREEN_H - 1 )) && return 1
    return 0
}

# ---- EnemyB ----
readonly EnemyBStaticTemplate='
    EnemyBObj ->
        {CLS} => EnemyB
        {SUP} => Enemy
        {MIX} => 
        {symbol} => B
        {hp} => 30
        {maxhp} => 30
        {score} => 500
        {w} => 5
        {h} => 3
    '
EnemyB_born () {
    local -n self=$1
    Enemy_born "$1"
    self["{art}$X"]=$' ___ \n| B |\n|___|'
}
EnemyB_move () {
    local -n self=$1
    _enemy_fire "$1" 3 '+' 3
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    (( cd < 14 )) && { self["{cd}$X"]=$cd ; return 0 ; }
    self["{cd}$X"]=0
    local _ay=${self["{y}$X"]} _ax=${self["{x}$X"]} _w=${self["{w}$X"]} _h=${self["{h}$X"]}
    _art_clear_at "$_ay" "$_ax" "${self["{art}$X"]}"
    (( _ay + _h < SCREEN_H )) && { printf '\033[%d;%dH%*s' $((_ay + _h)) "$_ax" 15 '' ; }
    local vx=${self["{vx}$X"]}
    (( RANDOM % 4 == 0 )) && vx=$(( (RANDOM % 3) - 1 ))
    self["{vx}$X"]=$vx
    local x=$(( _ax + vx ))
    (( x < 2 )) && x=2
    (( x > SCREEN_W - 2 - _w )) && x=$(( SCREEN_W - 2 - _w ))
    self["{x}$X"]=$x
    local vy=${self["{vy}$X"]}
    (( RANDOM % 8 == 0 )) && vy=$(( (RANDOM % 2) * 2 - 1 ))
    local y=$(( _ay + vy ))
    if (( y + _h >= SCREEN_H - 1 )) ; then
        y=$(( SCREEN_H - 2 - _h )) ; vy=-1
    elif (( y < GAME_TOP )) ; then
        y=$GAME_TOP ; vy=1
    fi
    self["{vy}$X"]=$vy
    self["{y}$X"]=$y
    return 0
}

# ---- Boss ----
readonly BossStaticTemplate='
    BossObj ->
        {CLS} => Boss
        {SUP} => Base
        {MIX} => 
        {x} => 0
        {y} => 0
        {w} => 13
        {h} => 5
        {art} => 
        {hp} => 100
        {maxhp} => 100
        {score} => 3000
        {cd} => 0
        {vx} => 1
        {symbol} => X
        {phase} => 0
    '
Boss_born () {
    local -n self=$1
    self["{x}$X"]=$(( (SCREEN_W - 13) / 2 ))
    self["{y}$X"]=$GAME_TOP
    self["{vx}$X"]=1
    self["{cd}$X"]=0
    self["{phase}$X"]=0
    self["{art}$X"]="$BOSS_ART_100"
}
Boss_move () {
    local -n self=$1

    local _hp=${self["{hp}$X"]} _maxhp=${self["{maxhp}$X"]}
    local _pct=$(( _hp * 100 / _maxhp ))
    local _newphase
    if (( _pct > 70 )) ; then
        _newphase=0
    elif (( _pct > 50 )) ; then
        _newphase=1
    elif (( _pct > 20 )) ; then
        _newphase=2
    else
        _newphase=3
    fi
    if (( _newphase != ${self["{phase}$X"]} )) ; then
        self["{phase}$X"]=$_newphase
        case "$_newphase" in
            0) self["{art}$X"]="$BOSS_ART_100" ;;
            1) self["{art}$X"]="$BOSS_ART_70" ;;
            2) self["{art}$X"]="$BOSS_ART_50" ;;
            3) self["{art}$X"]="$BOSS_ART_20" ;;
        esac
    fi

    local cd=$(( ${self["{cd}$X"]} + 1 ))
    if (( cd >= 6 )) ; then
        self["{cd}$X"]=0
        local _ay=${self["{y}$X"]} _ax=${self["{x}$X"]} _w=${self["{w}$X"]} _h=${self["{h}$X"]}
        _art_clear_at "$_ay" "$_ax" "${self["{art}$X"]}"
        (( _ay + _h < SCREEN_H )) && { printf '\033[%d;%dH%*s' $((_ay + _h)) "$_ax" 15 '' ; }
        local vx=${self["{vx}$X"]}
        local x=$(( _ax + vx ))
        if (( x < 2 )) ; then
            x=2 ; self["{vx}$X"]=1
        elif (( x + _w > SCREEN_W - 1 )) ; then
            x=$(( SCREEN_W - 1 - _w )) ; self["{vx}$X"]=-1
        fi
        self["{x}$X"]=$x
    else
        self["{cd}$X"]=$cd
    fi

    (( RANDOM % 100 < 3 )) || return 0
    local _by=$(( ${self["{y}$X"]} + ${self["{h}$X"]} ))
    local _bx=${self["{x}$X"]}
    local _b
    for _b in $((_bx + 4)) $((_bx + 6)) $((_bx + 8)) ; do
        xo_obj_born EnemyBullet "$_b" "$_by" '@' 3
        ENEMY_BULLETS+=("$REPLY")
    done
    return 0
}

# ===== Drop =====
readonly DropStaticTemplate='
    DropObj ->
        {CLS} => Drop
        {SUP} => Base
        {MIX} => 
        {x} => 0
        {y} => 0
        {symbol} => 1
        {dtype} => 1
        {cd} => 0
    '
Drop_born () {
    local -n self=$1
    self["{dtype}$X"]=$2
    self["{symbol}$X"]=$2
    self["{x}$X"]=$(( (RANDOM % (SCREEN_W - 4)) + 2 ))
    self["{y}$X"]=$GAME_TOP
    self["{cd}$X"]=0
}
Drop_move () {
    local -n self=$1
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    (( cd < 6 )) && { self["{cd}$X"]=$cd ; return 0 ; }
    self["{cd}$X"]=0
    printf '\033[%d;%dH ' "${self["{y}$X"]}" "${self["{x}$X"]}"
    self["{y}$X"]=$(( ${self["{y}$X"]} + 1 ))
    (( ${self["{y}$X"]} >= SCREEN_H - 1 )) && return 1
    return 0
}

# ===== HUD =====
draw_hud_line1 () {
    local -n p=$PLAYER
    local bt=${p["{bullet}$X"]}
    local weapon='.'
    if [[ -n "$bt" && -n "${XO_OBJ_POOL[$bt]+_}" ]] ; then
        local -n _bt=$bt
        weapon=${_bt["{symbol}$X"]}
        unset -n _bt
    fi
    printf '\033[1;1H\033[KHP:%d/%d  SCORE:%d  W:%s  BOMB:%d/5' \
        "${p["{hp}$X"]:-0}" 20 "${p["{score}$X"]:-0}" "$weapon" "${p["{bombs}$X"]:-0}"
    unset -n p
}
draw_hud_line2 () {
    printf '\033[2;1H\033[KENEMY V:1 Q:5 M:10 B:30 BOSS:100   BULLET .:1 *:2 #:3 &:4 |:LASER   DROP H:+3 b:BOMB m:MISSILE'
}
draw_bonus_hud () {
    local -n p=$PLAYER
    local t2=$(( ${p["{t2}$X"]:-0} / FPS ))
    local t3=$(( ${p["{t3}$X"]:-0} / FPS ))
    local t4=$(( ${p["{t4}$X"]:-0} / FPS ))
    local t5=$(( ${p["{t5}$X"]:-0} / FPS ))
    local mt=$(( ${p["{mt}$X"]:-0} / FPS ))
    unset -n p
    printf '\033[3;1H\033[KBONUS  *:%3d  #:%3d  &:%3d  |:%3d  M:%3d' "$t2" "$t3" "$t4" "$t5" "$mt"
}

# ===== render =====
render () {
    local -n p=$PLAYER
    local _px=${p["{x}$X"]} _py=${p["{y}$X"]}
    local _part=${p["{art}$X"]}
    local _pax=$(( _px - 1 ))
    local _pay=$_py
    local _pr=0 _prest=$_part
    while [[ -n "$_prest" ]] ; do
        local _pline=${_prest%%$'\n'*}
        if [[ "$_prest" == *$'\n'* ]] ; then
            _prest=${_prest#*$'\n'}
        else
            _prest=''
        fi
        printf '\033[%d;%dH%s%s%s' $((_pay + _pr)) "$_pax" "$C_BLUE" "$_pline" "$C_RESET"
        ((_pr++))
    done
    unset -n p

    local b e d eb m

    for b in "${BULLETS[@]}" ; do
        [[ -n "$b" && -n "${XO_OBJ_POOL[$b]+_}" ]] || continue
        local -n _b=$b
        local _bsym=${_b["{symbol}$X"]}
        if [[ "$_bsym" == "|" ]] ; then
            printf '\033[%d;%dH%s%s%s' "${_b["{y}$X"]}" "${_b["{x}$X"]}" "$C_PURPLE" "$_bsym" "$C_RESET"
        else
            printf '\033[%d;%dH%s' "${_b["{y}$X"]}" "${_b["{x}$X"]}" "$_bsym"
        fi
        unset -n _b
    done

    for m in "${MISSILES[@]}" ; do
        [[ -n "$m" && -n "${XO_OBJ_POOL[$m]+_}" ]] || continue
        local -n _m=$m
        printf '\033[%d;%dH%s%s%s' "${_m["{y}$X"]}" "${_m["{x}$X"]}" "$C_MAGENTA" "${_m["{symbol}$X"]}" "$C_RESET"
        unset -n _m
    done

    for eb in "${ENEMY_BULLETS[@]}" ; do
        [[ -n "$eb" && -n "${XO_OBJ_POOL[$eb]+_}" ]] || continue
        local -n _eb=$eb
        printf '\033[%d;%dH%s' "${_eb["{y}$X"]}" "${_eb["{x}$X"]}" "${_eb["{symbol}$X"]}"
        unset -n _eb
    done

    for e in "${ENEMIES[@]}" ; do
        [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
        local -n _e=$e
        local _cls=${_e["{CLS}$X"]}
        local _color=''
        case "$_cls" in
            Boss|EnemyB) _color=$C_RED ;;
            EnemyM)      _color=$C_ORANGE ;;
            EnemyQ)      _color=$C_YELLOW ;;
            EnemyV)      _color=$C_GREEN ;;
        esac

        local _ay=${_e["{y}$X"]} _ax=${_e["{x}$X"]}
        local _h=${_e["{h}$X"]}
        local _hp=${_e["{hp}$X"]}
        local _maxhp=${_e["{maxhp}$X"]}
        local _art=${_e["{art}$X"]}
        local _r=0 _rest=$_art
        while [[ -n "$_rest" ]] ; do
            local _line=${_rest%%$'\n'*}
            if [[ "$_rest" == *$'\n'* ]] ; then
                _rest=${_rest#*$'\n'}
            else
                _rest=''
            fi
            printf '\033[%d;%dH%s%s%s' $((_ay + _r)) "$_ax" "$_color" "$_line" "$C_RESET"
            ((_r++))
        done

        if [[ "$_cls" == "Boss" ]] || [[ "$_cls" == "EnemyB" ]] || [[ "$_cls" == "EnemyM" ]] ; then
            if (( _ay + _h < SCREEN_H )) ; then
                printf '\033[%d;%dH%s[%d/%d]%s' $((_ay + _h)) "$_ax" \
                    "$_color" "$_hp" "$_maxhp" "$C_RESET"
            fi
        fi
        unset -n _e
    done

    for d in "${DROPS[@]}" ; do
        [[ -n "$d" && -n "${XO_OBJ_POOL[$d]+_}" ]] || continue
        local -n _d=$d
        printf '\033[%d;%dH%s' "${_d["{y}$X"]}" "${_d["{x}$X"]}" "${_d["{symbol}$X"]}"
        unset -n _d
    done
}

render_bomb_fx () {
    local i
    for (( i=0; i<${#BOMB_FX_POS[@]}; i+=2 )) ; do
        printf '\033[%d;%dH ' "${BOMB_FX_POS[i]}" "${BOMB_FX_POS[i+1]}"
    done
    BOMB_FX_POS=()

    local _chars='@#$%&*?!'
    local _colors=("$C_RED" "$C_YELLOW" "$C_ORANGE" "$C_PURPLE" "$C_BLUE")
    local _n=$(( 15 + RANDOM % 10 ))
    local _i2 _cx _cy _ch _ci
    for (( _i2=0; _i2<_n; _i2++ )) ; do
        _cx=$(( RANDOM % (SCREEN_W - 2) + 2 ))
        _cy=$(( RANDOM % (SCREEN_H - GAME_TOP) + GAME_TOP ))
        _ch=${_chars:RANDOM % ${#_chars}:1}
        _ci=$(( RANDOM % 5 ))
        printf '\033[%d;%dH%s%s%s' "$_cy" "$_cx" "${_colors[_ci]}" "$_ch" "$C_RESET"
        BOMB_FX_POS+=("$_cy" "$_cx")
    done
}

render_boss_fx () {
    local i
    for (( i=0; i<${#BOSS_FX_POS[@]}; i+=2 )) ; do
        printf '\033[%d;%dH ' "${BOSS_FX_POS[i]}" "${BOSS_FX_POS[i+1]}"
    done
    BOSS_FX_POS=()

    local _chars='@#*%&!?'
    local _colors=("$C_RED" "$C_YELLOW" "$C_ORANGE")
    local _n=24
    local _i2 _cx _cy _ch _ci _dx _dy
    for (( _i2=0; _i2<_n; _i2++ )) ; do
        _dx=$(( RANDOM % 21 - 10 ))
        _dy=$(( RANDOM % 11 - 5 ))
        _cx=$(( BOSS_FX_CX + _dx ))
        _cy=$(( BOSS_FX_CY + _dy ))
        (( _cx < 2 )) && _cx=2
        (( _cx >= SCREEN_W - 1 )) && _cx=$(( SCREEN_W - 2 ))
        (( _cy < GAME_TOP )) && _cy=$GAME_TOP
        (( _cy >= SCREEN_H - 1 )) && _cy=$(( SCREEN_H - 2 ))
        _ch=${_chars:RANDOM % ${#_chars}:1}
        _ci=$(( RANDOM % 3 ))
        printf '\033[%d;%dH%s%s%s' "$_cy" "$_cx" "${_colors[_ci]}" "$_ch" "$C_RESET"
        BOSS_FX_POS+=("$_cy" "$_cx")
    done
}

# ===== 存档 =====
save_game () {
    local -A SAVE=()
    x_init "$X_TYPE_OBJ" ; SAVE=($REPLY)
    x_insert SAVE "{meta}$X{version}$X" 1
    x_insert SAVE "{meta}$X{player}$X" "$PLAYER"
    x_insert SAVE "{meta}$X{obj_seq}$X" "$XO_OBJ_SEQ"

    local obj k
    for obj in "${!XO_OBJ_POOL[@]}" ; do
        local -n _o=$obj
        for k in "${!_o[@]}" ; do
            [[ "$k" == '{'*"$X" ]] || continue
            x_insert SAVE "{objs}$X{$obj}$X$k" "${_o[$k]}" || continue
        done
        unset -n _o
    done

    local i
    for i in "${!BULLETS[@]}" ; do
        x_insert SAVE "{lists}$X{bullets}$X[$i]$X" "${BULLETS[$i]}"
    done
    for i in "${!ENEMIES[@]}" ; do
        x_insert SAVE "{lists}$X{enemies}$X[$i]$X" "${ENEMIES[$i]}"
    done
    for i in "${!DROPS[@]}" ; do
        x_insert SAVE "{lists}$X{drops}$X[$i]$X" "${DROPS[$i]}"
    done
    for i in "${!ENEMY_BULLETS[@]}" ; do
        x_insert SAVE "{lists}$X{ebullets}$X[$i]$X" "${ENEMY_BULLETS[$i]}"
    done
    for i in "${!MISSILES[@]}" ; do
        x_insert SAVE "{lists}$X{missiles}$X[$i]$X" "${MISSILES[$i]}"
    done

    x_dump SAVE '' 4 6 > "$STRAFE_SAVE_FILE"
    return 0
}

load_game () {
    [[ -f "$STRAFE_SAVE_FILE" ]] || return 1
    local dump
    dump=$(<"$STRAFE_SAVE_FILE")
    [[ -n "$dump" ]] || return 1

    x_rebuild_from_dump "$dump" || return 1
    local -A SAVE=($REPLY)

    [[ "${SAVE[{meta}$X{version}$X]:-}" == "1" ]] || return 1

    local obj
    for obj in "${!XO_OBJ_POOL[@]}" ; do
        unset -v "$obj"
    done
    XO_OBJ_POOL=()
    BULLETS=() ; ENEMIES=() ; DROPS=() ; ENEMY_BULLETS=() ; MISSILES=()

    local k rest obj_tok o after field_tok v
    local -A declared=()
    for k in "${!SAVE[@]}" ; do
        [[ "$k" == "{objs}$X"* ]] || continue
        rest=${k#"{objs}$X"}
        obj_tok=${rest%%"$X"*}
        o=${obj_tok:1:-1}
        after=${rest#*"$X"}
        [[ -z "$after" ]] && continue
        field_tok=${after%%"$X"*}
        [[ "$after" != "${field_tok}$X" ]] && continue
        v=${SAVE[$k]}
        [[ "$v" == "$X_VALUE_NULL" ]] && continue

        if [[ -z "${declared[$o]+_}" ]] ; then
            declare -gA "$o=()"
            declared[$o]=1
        fi
        local -n _t=$o
        _t["${field_tok}$X"]=$v
        unset -n _t
    done

    for o in "${!declared[@]}" ; do
        local -n _t=$o
        XO_OBJ_POOL[$o]=${_t["{CLS}$X"]}
        unset -n _t
    done

    PLAYER=${SAVE[{meta}$X{player}$X]}
    XO_OBJ_SEQ=${SAVE[{meta}$X{obj_seq}$X]}

    local list_tok list idx_tok idx
    for k in "${!SAVE[@]}" ; do
        [[ "$k" == "{lists}$X"* ]] || continue
        rest=${k#"{lists}$X"}
        list_tok=${rest%%"$X"*}
        list=${list_tok:1:-1}
        after=${rest#*"$X"}
        [[ -z "$after" ]] && continue
        idx_tok=${after%%"$X"*}
        [[ "$after" != "${idx_tok}$X" ]] && continue
        idx=${idx_tok:1:-1}
        v=${SAVE[$k]}
        case "$list" in
            bullets)   BULLETS[$idx]=$v ;;
            enemies)   ENEMIES[$idx]=$v ;;
            drops)     DROPS[$idx]=$v ;;
            ebullets)  ENEMY_BULLETS[$idx]=$v ;;
            missiles)  MISSILES[$idx]=$v ;;
        esac
    done

    return 0
}

# ===== 终端恢复 =====
term_restore () {
    stty sane
    cursor_show
    printf '%s' "$C_RESET"
    screen_clear
}

# ===== 每局初始化 =====
init_game () {
    local -n p=$PLAYER
    p["{x}$X"]=$(( SCREEN_W / 2 ))
    p["{y}$X"]=$(( SCREEN_H - 2 ))
    p["{hp}$X"]=20
    p["{score}$X"]=0
    p["{bombs}$X"]=0
    p["{t2}$X"]=0
    p["{t3}$X"]=0
    p["{t4}$X"]=0
    p["{t5}$X"]=0
    p["{mt}$X"]=0

    local old_bt=${p["{bullet}$X"]}
    [[ -n "$old_bt" && -n "${XO_OBJ_POOL[$old_bt]+_}" ]] && xo_obj_kill "$old_bt"
    xo_obj_born BulletType '.' 1
    p["{bullet}$X"]=$REPLY
    unset -n p

    local b e d eb m
    for b in "${BULLETS[@]}" ; do [[ -n "${XO_OBJ_POOL[$b]+_}" ]] && xo_obj_kill "$b" ; done
    for e in "${ENEMIES[@]}" ; do [[ -n "${XO_OBJ_POOL[$e]+_}" ]] && xo_obj_kill "$e" ; done
    for d in "${DROPS[@]}" ; do [[ -n "${XO_OBJ_POOL[$d]+_}" ]] && xo_obj_kill "$d" ; done
    for eb in "${ENEMY_BULLETS[@]}" ; do [[ -n "${XO_OBJ_POOL[$eb]+_}" ]] && xo_obj_kill "$eb" ; done
    for m in "${MISSILES[@]}" ; do [[ -n "${XO_OBJ_POOL[$m]+_}" ]] && xo_obj_kill "$m" ; done
    BULLETS=() ; ENEMIES=() ; DROPS=() ; ENEMY_BULLETS=() ; MISSILES=() ; BOMB_FX_POS=() ; BOSS_FX_POS=()
}

# ===== GAME OVER =====
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
    screen_clear
    game_over_banner
    printf '\n'
    printf 'press Enter to again, Press q to quit\n'
    local key
    while : ; do
        IFS= read -rsn1 key || true
        case "$key" in
            ''|$'\r'|$'\n') return 0 ;;
            q|Q)            return 1 ;;
        esac
    done
}

# ===== 单局主循环 =====
play_game () {
    local b e d eb m key dx dy running=1
    local enemy_tick=0 drop_tick=0 fire_cd=0 missile_cd=0 missile_side=0
    local b_dry=0 boss_dry=0
    local paused=0 paused_drawn=0
    local msg= msg_tick=0
    local inv=0
    local bomb_fx_tick=0
    local boss_fx_tick=0
    local hud_tick=0
    local last_bonus_str='__init__'

    while : ; do
        ((fire_cd > 0)) && ((fire_cd--))
        ((missile_cd > 0)) && ((missile_cd--))
        (( inv > 0 )) && ((inv--))

        if (( hud_tick % 6 == 0 )) ; then
            draw_hud_line1
            draw_hud_line2
        fi
        ((hud_tick++))

        local -n _pbh=$PLAYER
        local _cbs="$(( ${_pbh["{t2}$X"]:-0} / FPS )) $(( ${_pbh["{t3}$X"]:-0} / FPS )) $(( ${_pbh["{t4}$X"]:-0} / FPS )) $(( ${_pbh["{t5}$X"]:-0} / FPS )) $(( ${_pbh["{mt}$X"]:-0} / FPS ))"
        unset -n _pbh
        if [[ "$_cbs" != "$last_bonus_str" ]] ; then
            draw_bonus_hud
            last_bonus_str=$_cbs
        fi

        local -n _pb=$PLAYER
        local _bt=${_pb["{bullet}$X"]}
        local _sym='.'
        if [[ -n "$_bt" && -n "${XO_OBJ_POOL[$_bt]+_}" ]] ; then
            local -n _bo=$_bt
            _sym=${_bo["{symbol}$X"]}
            unset -n _bo
        fi
        local _tk=''
        case "$_sym" in
            '*') _tk="{t2}$X" ;;
            '#') _tk="{t3}$X" ;;
            '&') _tk="{t4}$X" ;;
            '|') _tk="{t5}$X" ;;
        esac
        if [[ -n "$_tk" ]] ; then
            local _tv=${_pb[$_tk]:-0}
            if (( _tv > 0 )) ; then
                _pb["$_tk"]=$(( _tv - 1 ))
                (( _tv - 1 == 0 )) && {
                    local _old=${_pb["{bullet}$X"]}
                    [[ -n "$_old" && -n "${XO_OBJ_POOL[$_old]+_}" ]] && xo_obj_kill "$_old"
                    xo_obj_born BulletType '.' 1
                    _pb["{bullet}$X"]=$REPLY
                }
            fi
        fi
        local _mt=${_pb["{mt}$X"]:-0}
        (( _mt > 0 )) && _pb["{mt}$X"]=$(( _mt - 1 ))
        unset -n _pb

        dx=0 ; dy=0 ; local want_bomb=0
        while IFS= read -rsn1 -t 0.02 key ; do
            case "$key" in
                p|P) paused=$((1-paused)) ; paused_drawn=0 ;;
                q|Q) running=0 ; break ;;
                s|S)
                    if (( paused )) ; then
                        save_game
                        msg="SAVED" ; msg_tick=50
                    else
                        dy=1
                    fi
                    ;;
                l|L)
                    if (( paused )) ; then
                        if load_game ; then
                            screen_clear
                            msg="LOADED" ; msg_tick=50
                        else
                            msg="LOAD FAILED" ; msg_tick=50
                        fi
                    else
                        dx=1
                    fi
                    ;;
                a|A|h|H) (( paused )) || dx=-1 ;;
                d|D)     (( paused )) || dx=1  ;;
                w|W|k|K) (( paused )) || dy=-1 ;;
                j|J)     (( paused )) || dy=1  ;;
                ' ')
                    if (( !paused )) ; then
                        local -n _bp_tmp=$PLAYER
                        if (( ${_bp_tmp["{bombs}$X"]:-0} > 0 )) ; then
                            want_bomb=1
                        fi
                        unset -n _bp_tmp
                    fi
                    ;;
            esac
        done
        ((running)) || return 1

        if (( want_bomb )) ; then
            local -n _bp=$PLAYER
            _bp["{bombs}$X"]=$(( ${_bp["{bombs}$X"]:-0} - 1 ))
            unset -n _bp

            local _ceb
            for _ceb in "${ENEMY_BULLETS[@]}" ; do
                [[ -n "$_ceb" && -n "${XO_OBJ_POOL[$_ceb]+_}" ]] || continue
                local -n _ce=$_ceb
                printf '\033[%d;%dH ' "${_ce["{y}$X"]}" "${_ce["{x}$X"]}"
                unset -n _ce
                xo_obj_kill "$_ceb"
            done
            ENEMY_BULLETS=()

            local -a bomb_alive=()
            local bomb_score=0
            for e in "${ENEMIES[@]}" ; do
                [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
                local -n _e=$e
                local new_hp=$(( ${_e["{hp}$X"]} - 10 ))
                _e["{hp}$X"]=$new_hp
                local escore=${_e["{score}$X"]}
                local _ay=${_e["{y}$X"]} _ax=${_e["{x}$X"]}
                local _art=${_e["{art}$X"]} _h=${_e["{h}$X"]}
                local _ecls=${_e["{CLS}$X"]}
                local _ew=${_e["{w}$X"]} _eh=${_e["{h}$X"]}
                unset -n _e
                if (( new_hp <= 0 )) ; then
                    bomb_score=$(( bomb_score + escore ))
                    _art_clear_at "$_ay" "$_ax" "$_art"
                    (( _ay + _h < SCREEN_H )) && { printf '\033[%d;%dH%*s' $((_ay + _h)) "$_ax" 15 '' ; }
                    if [[ "$_ecls" == "Boss" ]] ; then
                        BOSS_FX_CX=$(( _ax + _ew / 2 ))
                        BOSS_FX_CY=$(( _ay + _eh / 2 ))
                        boss_fx_tick=60
                    fi
                    xo_obj_kill "$e"
                else
                    bomb_alive+=("$e")
                fi
            done
            ENEMIES=("${bomb_alive[@]}")
            local -n _bp2=$PLAYER
            _bp2["{score}$X"]=$(( ${_bp2["{score}$X"]:-0} + bomb_score ))
            unset -n _bp2
            bomb_fx_tick=50
        fi

        if (( paused )) ; then
            if (( !paused_drawn )) ; then
                printf '\033[4;1H\033[KPAUSED  (p=resume  q=quit  s=save  l=load)'
                paused_drawn=1
            fi
            if (( msg_tick > 0 )) ; then
                printf '\033[4;1H\033[K%s' "$msg"
                ((msg_tick--))
                if (( msg_tick == 0 )) ; then paused_drawn=0 ; fi
            fi
            continue
        fi
        if (( paused_drawn )) ; then
            printf '\033[4;1H\033[K'
            paused_drawn=0
        fi

        (( dx || dy )) && xo_call "$PLAYER" move "$dx" "$dy"

        if (( fire_cd == 0 )) ; then
            xo_call "$PLAYER" fire
            local -n _pp=$PLAYER
            local _fbt=${_pp["{bullet}$X"]}
            local _fsym='.'
            if [[ -n "$_fbt" && -n "${XO_OBJ_POOL[$_fbt]+_}" ]] ; then
                local -n _fbo=$_fbt
                _fsym=${_fbo["{symbol}$X"]}
                unset -n _fbo
            fi
            unset -n _pp
            if [[ "$_fsym" == "|" ]] ; then fire_cd=3 ; else fire_cd=6 ; fi
        fi

        # 导弹发射（独立于主武器，发射位置钳制在 [2, SCREEN_W-2]）
        local -n _pm=$PLAYER
        if (( ${_pm["{mt}$X"]:-0} > 0 && missile_cd == 0 )) ; then
            local _my=$(( ${_pm["{y}$X"]} - 1 ))
            local _mx
            if (( missile_side )) ; then
                _mx=$(( ${_pm["{x}$X"]} - 1 ))
                missile_side=0
            else
                _mx=$(( ${_pm["{x}$X"]} + 1 ))
                missile_side=1
            fi
            (( _mx < 2 )) && _mx=2
            (( _mx > SCREEN_W - 2 )) && _mx=$(( SCREEN_W - 2 ))
            xo_obj_born Missile "$_mx" "$_my" 2
            MISSILES+=("$REPLY")
            missile_cd=10
        fi
        unset -n _pm

        local -a alive_b=()
        for b in "${BULLETS[@]}" ; do
            [[ -n "$b" && -n "${XO_OBJ_POOL[$b]+_}" ]] || continue
            xo_call "$b" move
            local -n _b=$b
            if (( ${_b["{y}$X"]} < GAME_TOP )) ; then
                unset -n _b
                xo_obj_kill "$b"
            else
                unset -n _b
                alive_b+=("$b")
            fi
        done
        BULLETS=("${alive_b[@]}")

        local -a alive_m=()
        for m in "${MISSILES[@]}" ; do
            [[ -n "$m" && -n "${XO_OBJ_POOL[$m]+_}" ]] || continue
            xo_call "$m" move
            if (( $? == 0 )) ; then
                alive_m+=("$m")
            else
                xo_obj_kill "$m"
            fi
        done
        MISSILES=("${alive_m[@]}")

        local -a alive_eb=()
        for eb in "${ENEMY_BULLETS[@]}" ; do
            [[ -n "$eb" && -n "${XO_OBJ_POOL[$eb]+_}" ]] || continue
            local ey ex
            local -n _eb=$eb
            ey=${_eb["{y}$X"]} ; ex=${_eb["{x}$X"]}
            unset -n _eb
            xo_call "$eb" move
            if (( $? == 0 )) ; then
                alive_eb+=("$eb")
            else
                printf '\033[%d;%dH ' "$ey" "$ex"
                xo_obj_kill "$eb"
            fi
        done
        ENEMY_BULLETS=("${alive_eb[@]}")

        local -a alive_e=()
        for e in "${ENEMIES[@]}" ; do
            [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
            xo_call "$e" move
            if (( $? == 0 )) ; then
                alive_e+=("$e")
            else
                xo_obj_kill "$e"
            fi
        done
        ENEMIES=("${alive_e[@]}")

        local -a alive_d=()
        for d in "${DROPS[@]}" ; do
            [[ -n "$d" && -n "${XO_OBJ_POOL[$d]+_}" ]] || continue
            local dy_pos dx_pos
            local -n _d=$d
            dy_pos=${_d["{y}$X"]} ; dx_pos=${_d["{x}$X"]}
            unset -n _d
            xo_call "$d" move
            if (( $? == 0 )) ; then
                alive_d+=("$d")
            else
                printf '\033[%d;%dH ' "$dy_pos" "$dx_pos"
                xo_obj_kill "$d"
            fi
        done
        DROPS=("${alive_d[@]}")

        local -A killed_b=() killed_m=() killed_e=()
        local score_gain=0

        for b in "${BULLETS[@]}" ; do
            [[ -n "${killed_b[$b]+_}" ]] && continue
            [[ -n "$b" && -n "${XO_OBJ_POOL[$b]+_}" ]] || continue
            local -n _b=$b
            local bx=${_b["{x}$X"]} by=${_b["{y}$X"]}
            local bdmg=${_b["{damage}$X"]}
            unset -n _b

            for e in "${ENEMIES[@]}" ; do
                [[ -n "${killed_e[$e]+_}" ]] && continue
                [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
                local -n _e=$e
                local _ex=${_e["{x}$X"]} _ey=${_e["{y}$X"]}
                local _ew=${_e["{w}$X"]} _eh=${_e["{h}$X"]}

                if (( bx >= _ex && bx < _ex + _ew && by >= _ey && by < _ey + _eh )) ; then
                    local new_hp=$(( ${_e["{hp}$X"]} - bdmg ))
                    _e["{hp}$X"]=$new_hp
                    local escore=${_e["{score}$X"]}
                    local _art=${_e["{art}$X"]} _h=${_e["{h}$X"]}
                    local _ecls=${_e["{CLS}$X"]} _ew2=${_e["{w}$X"]} _eh2=${_e["{h}$X"]}
                    unset -n _e
                    killed_b[$b]=1
                    if (( new_hp <= 0 )) ; then
                        killed_e[$e]=1
                        score_gain=$(( score_gain + escore ))
                        _art_clear_at "$_ey" "$_ex" "$_art"
                        (( _ey + _h < SCREEN_H )) && { printf '\033[%d;%dH%*s' $((_ey + _h)) "$_ex" 15 '' ; }
                        if [[ "$_ecls" == "Boss" ]] ; then
                            BOSS_FX_CX=$(( _ex + _ew2 / 2 ))
                            BOSS_FX_CY=$(( _ey + _eh2 / 2 ))
                            boss_fx_tick=60
                        fi
                        xo_obj_kill "$e"
                    fi
                    break
                fi
                unset -n _e
            done
        done

        for m in "${MISSILES[@]}" ; do
            [[ -n "${killed_m[$m]+_}" ]] && continue
            [[ -n "$m" && -n "${XO_OBJ_POOL[$m]+_}" ]] || continue
            local -n _m=$m
            local mx=${_m["{x}$X"]} my=${_m["{y}$X"]}
            local mdmg=${_m["{damage}$X"]}
            unset -n _m

            for e in "${ENEMIES[@]}" ; do
                [[ -n "${killed_e[$e]+_}" ]] && continue
                [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
                local -n _e=$e
                local _ex=${_e["{x}$X"]} _ey=${_e["{y}$X"]}
                local _ew=${_e["{w}$X"]} _eh=${_e["{h}$X"]}

                if (( mx >= _ex && mx < _ex + _ew && my >= _ey && my < _ey + _eh )) ; then
                    local new_hp=$(( ${_e["{hp}$X"]} - mdmg ))
                    _e["{hp}$X"]=$new_hp
                    local escore=${_e["{score}$X"]}
                    local _art=${_e["{art}$X"]} _h=${_e["{h}$X"]}
                    local _ecls=${_e["{CLS}$X"]} _ew2=${_e["{w}$X"]} _eh2=${_e["{h}$X"]}
                    unset -n _e
                    killed_m[$m]=1
                    if (( new_hp <= 0 )) ; then
                        killed_e[$e]=1
                        score_gain=$(( score_gain + escore ))
                        _art_clear_at "$_ey" "$_ex" "$_art"
                        (( _ey + _h < SCREEN_H )) && { printf '\033[%d;%dH%*s' $((_ey + _h)) "$_ex" 15 '' ; }
                        if [[ "$_ecls" == "Boss" ]] ; then
                            BOSS_FX_CX=$(( _ex + _ew2 / 2 ))
                            BOSS_FX_CY=$(( _ey + _eh2 / 2 ))
                            boss_fx_tick=60
                        fi
                        xo_obj_kill "$e"
                    fi
                    break
                fi
                unset -n _e
            done
        done

        if ((${#killed_b[@]})) ; then
            local -a nb=()
            for b in "${BULLETS[@]}" ; do
                if [[ -n "${killed_b[$b]+_}" ]] ; then
                    [[ -n "$b" && -n "${XO_OBJ_POOL[$b]+_}" ]] || continue
                    local -n _b=$b
                    printf '\033[%d;%dH ' "${_b["{y}$X"]}" "${_b["{x}$X"]}"
                    unset -n _b
                    xo_obj_kill "$b"
                else
                    nb+=("$b")
                fi
            done
            BULLETS=("${nb[@]}")
        fi

        if ((${#killed_m[@]})) ; then
            local -a nm=()
            for m in "${MISSILES[@]}" ; do
                if [[ -n "${killed_m[$m]+_}" ]] ; then
                    [[ -n "$m" && -n "${XO_OBJ_POOL[$m]+_}" ]] || continue
                    local -n _m=$m
                    printf '\033[%d;%dH ' "${_m["{y}$X"]}" "${_m["{x}$X"]}"
                    unset -n _m
                    xo_obj_kill "$m"
                else
                    nm+=("$m")
                fi
            done
            MISSILES=("${nm[@]}")
        fi

        if ((${#killed_e[@]})) ; then
            local -a ne=()
            for e in "${ENEMIES[@]}" ; do
                [[ -n "${killed_e[$e]+_}" ]] || ne+=("$e")
            done
            ENEMIES=("${ne[@]}")
        fi

        local -n p=$PLAYER
        local px=${p["{x}$X"]} py=${p["{y}$X"]}
        local player_dmg=0

        local -a survive_eb=()
        for eb in "${ENEMY_BULLETS[@]}" ; do
            [[ -n "$eb" && -n "${XO_OBJ_POOL[$eb]+_}" ]] || continue
            local -n _eb=$eb
            if (( ${_eb["{x}$X"]} == px && ${_eb["{y}$X"]} == py )) ; then
                player_dmg=$(( player_dmg + ${_eb["{damage}$X"]} ))
                printf '\033[%d;%dH ' "${_eb["{y}$X"]}" "${_eb["{x}$X"]}"
                unset -n _eb
                xo_obj_kill "$eb"
            else
                unset -n _eb
                survive_eb+=("$eb")
            fi
        done
        ENEMY_BULLETS=("${survive_eb[@]}")

        for e in "${ENEMIES[@]}" ; do
            [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
            local -n _e=$e
            local _ex=${_e["{x}$X"]} _ey=${_e["{y}$X"]}
            local _ew=${_e["{w}$X"]} _eh=${_e["{h}$X"]}
            if (( px >= _ex && px < _ex + _ew && py >= _ey && py < _ey + _eh )) ; then
                player_dmg=$(( player_dmg + 3 ))
            fi
            unset -n _e
        done

        if (( player_dmg > 0 && inv == 0 )) ; then
            p["{hp}$X"]=$(( ${p["{hp}$X"]} - player_dmg ))
            inv=30
        fi

        if (( score_gain > 0 )) ; then
            p["{score}$X"]=$(( ${p["{score}$X"]} + score_gain ))
        fi
        local hp=${p["{hp}$X"]}

        local -a survive_d2=()
        for d in "${DROPS[@]}" ; do
            [[ -n "$d" && -n "${XO_OBJ_POOL[$d]+_}" ]] || continue
            local -n _d=$d
            if (( ${_d["{x}$X"]} == px && ${_d["{y}$X"]} == py )) ; then
                local dtype=${_d["{dtype}$X"]}
                printf '\033[%d;%dH ' "${_d["{y}$X"]}" "${_d["{x}$X"]}"
                unset -n _d
                xo_obj_kill "$d"

                case "$dtype" in
                    1|3|4|5)
                        p["{t2}$X"]=0 ; p["{t3}$X"]=0 ; p["{t4}$X"]=0 ; p["{t5}$X"]=0
                        local bsym bdmg tfield
                        case "$dtype" in
                            1) bsym='*' ; bdmg=2 ; tfield=t2 ;;
                            3) bsym='#' ; bdmg=3 ; tfield=t3 ;;
                            4) bsym='&' ; bdmg=4 ; tfield=t4 ;;
                            5) bsym='|' ; bdmg=3 ; tfield=t5 ;;
                        esac
                        local old_bt=${p["{bullet}$X"]}
                        [[ -n "$old_bt" && -n "${XO_OBJ_POOL[$old_bt]+_}" ]] && xo_obj_kill "$old_bt"
                        xo_obj_born BulletType "$bsym" "$bdmg"
                        p["{bullet}$X"]=$REPLY
                        case "$tfield" in
                            t2) p["{t2}$X"]=$BONUS_T2 ;;
                            t3) p["{t3}$X"]=$BONUS_T3 ;;
                            t4) p["{t4}$X"]=$BONUS_T4 ;;
                            t5) p["{t5}$X"]=$BONUS_T5 ;;
                        esac
                        ;;
                    H)
                        p["{hp}$X"]=$(( ${p["{hp}$X"]} + 3 ))
                        (( ${p["{hp}$X"]} > 20 )) && p["{hp}$X"]=20
                        ;;
                    b)
                        if (( ${p["{bombs}$X"]:-0} < 5 )) ; then
                            p["{bombs}$X"]=$(( ${p["{bombs}$X"]:-0} + 1 ))
                        fi
                        ;;
                    m)
                        p["{mt}$X"]=$BONUS_MT
                        ;;
                esac
            else
                unset -n _d
                survive_d2+=("$d")
            fi
        done
        DROPS=("${survive_d2[@]}")
        unset -n p

        (( hp <= 0 )) && return 0

        (( enemy_tick++ % 50 == 0 )) && {
            local alive_B=0 alive_Boss=0
            for e in "${ENEMIES[@]}" ; do
                [[ -n "$e" && -n "${XO_OBJ_POOL[$e]+_}" ]] || continue
                local -n _e=$e
                local _c=${_e["{CLS}$X"]}
                [[ "$_c" == "EnemyB" ]] && ((alive_B++))
                [[ "$_c" == "Boss"   ]] && ((alive_Boss++))
                unset -n _e
            done

            local spawn_cls=''
            local _r=$(( RANDOM % 1000 ))
            if (( alive_Boss >= 2 )) ; then
                if (( _r < 600 )) ; then spawn_cls=EnemyV
                elif (( _r < 850 )) ; then spawn_cls=EnemyQ
                elif (( _r < 950 )) ; then spawn_cls=EnemyM
                else                       spawn_cls=EnemyB
                fi
            else
                if (( boss_dry >= 100 )) ; then
                    spawn_cls=Boss ; boss_dry=0
                elif (( b_dry >= 30 && alive_B == 0 )) ; then
                    spawn_cls=EnemyB ; b_dry=0
                elif (( _r < 450 )) ; then spawn_cls=EnemyV
                elif (( _r < 700 )) ; then spawn_cls=EnemyQ
                elif (( _r < 800 )) ; then spawn_cls=EnemyM
                elif (( _r < 950 )) ; then spawn_cls=EnemyB
                else                       spawn_cls=Boss
                fi
            fi

            if [[ "$spawn_cls" == "Boss" ]] ; then
                boss_dry=0
            else
                ((boss_dry++))
            fi
            if [[ "$spawn_cls" == "EnemyB" ]] ; then b_dry=0
            elif [[ "$spawn_cls" != "Boss" ]] ; then ((b_dry++))
            fi
            xo_obj_born "$spawn_cls"
            ENEMIES+=("$REPLY")
        }

        (( drop_tick++ % 100 == 0 )) && (( RANDOM % 100 < 60 )) && {
            local _dts=(1 3 4 5 H b m)
            xo_obj_born Drop "${_dts[RANDOM % 7]}"
            DROPS+=("$REPLY")
        }

        if (( msg_tick > 0 )) ; then
            printf '\033[4;1H\033[K%s' "$msg"
            ((msg_tick--))
            if (( msg_tick == 0 )) ; then
                printf '\033[4;1H\033[K'
            fi
        fi

        render

        if (( bomb_fx_tick > 0 )) ; then
            render_bomb_fx
            ((bomb_fx_tick--))
        elif (( ${#BOMB_FX_POS[@]} > 0 )) ; then
            local _bi
            for (( _bi=0; _bi<${#BOMB_FX_POS[@]}; _bi+=2 )) ; do
                printf '\033[%d;%dH ' "${BOMB_FX_POS[_bi]}" "${BOMB_FX_POS[_bi+1]}"
            done
            BOMB_FX_POS=()
        fi

        if (( boss_fx_tick > 0 )) ; then
            render_boss_fx
            ((boss_fx_tick--))
        elif (( ${#BOSS_FX_POS[@]} > 0 )) ; then
            local _bfi
            for (( _bfi=0; _bfi<${#BOSS_FX_POS[@]}; _bfi+=2 )) ; do
                printf '\033[%d;%dH ' "${BOSS_FX_POS[_bfi]}" "${BOSS_FX_POS[_bfi+1]}"
            done
            BOSS_FX_POS=()
        fi
    done
}

# ===== 主入口 =====
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

main


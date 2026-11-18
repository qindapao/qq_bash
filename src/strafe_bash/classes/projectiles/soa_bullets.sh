# classes/projectiles/soa_bullets.sh — 单格弹丸（SoA：平行数组，脱离对象系统）
#
# 为什么单独做：每发弹丸每 tick 原来要付 方法调用 + nameref 绑定 + 若干次哈希数组
# 读写（~155µs）。弹丸没有任何多态/mixin/生命周期回调，纯粹是"一堆数"，所以改成
# 平行数组 + 槽位：每发只剩数组下标与算术（~30µs）。
#
# 槽位复用：死亡时把槽压进空闲栈，出生优先取空闲槽；不压缩，槽号稳定，
# 帧缓冲归属用 "E$槽号" 这个短句柄。
#
# 巨型/多格弹不进这里：它们有 art、有血量，属于对象层（和敌人同构）。
[[ -n "${_STRAFE_SOA_BULLETS_SH:-}" ]] && return 0
_STRAFE_SOA_BULLETS_SH=1
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/render/fb.sh"

# 类型：0=直下 EnemyBullet（每 4 tick 一格） 1=矢量 BossBullet 2=追踪 EnemyMissile
declare -gai EB_ALIVE=() EB_TYPE=() EB_X=() EB_Y=() EB_VX=() EB_VY=() \
             EB_STEP=() EB_CD=() EB_DMG=() EB_FUEL=()
declare -ga  EB_GLYPH=() EB_TAG=()
declare -gai EB_N=0 EB_LIVE=0
declare -gai EB_FREE=()

# 新局/读档：全部清空
eb_reset () {
    EB_ALIVE=() EB_TYPE=() EB_X=() EB_Y=() EB_VX=() EB_VY=() \
    EB_STEP=() EB_CD=() EB_DMG=() EB_FUEL=() EB_GLYPH=() EB_TAG=() EB_FREE=()
    EB_N=0 EB_LIVE=0
    return 0
}

# 出生：取一个槽（优先空闲栈），写字段并占格
# $1=type $2=x $3=y $4=vx $5=vy $6=step $7=cd $8=damage $9=glyph $10=fuel
eb_add () {
    local -i i
    if (( ${#EB_FREE[@]} )) ; then
        i=${EB_FREE[-1]}
        unset 'EB_FREE[-1]'
    else
        (( EB_N >= ENEMY_BULLET_LIMIT )) && return 1
        i=$EB_N
        (( EB_N++ ))
    fi
    EB_ALIVE[i]=1 EB_TYPE[i]=$1 EB_X[i]=$2 EB_Y[i]=$3 EB_VX[i]=$4 EB_VY[i]=$5 \
    EB_STEP[i]=$6 EB_CD[i]=$7 EB_DMG[i]=$8 EB_GLYPH[i]=$9 EB_FUEL[i]=${10:-0} \
    EB_TAG[i]="E$i"
    (( EB_LIVE++ ))
    local -i _fi=$(( ($3 - 1) * FB_W + ($2 - 1) ))
    # owner 存 1-based 槽位号（整数比较比字符串快）；空 owner=0 不会与任何槽冲突
    FB_CELL[_fi]=$9 FB_OWNER[_fi]=$(( i + 1 )) FB_DIRTY+=("$_fi")
    return 0
}

# 死亡：清掉自己占的格，槽位回收到空闲栈
eb_kill () {
    local -i i=$1
    (( EB_ALIVE[i] )) || return 0
    local -i x=${EB_X[i]} y=${EB_Y[i]} _fi _ticket=$(( i + 1 ))
    if (( x >= 2 && x <= SCREEN_W - 2 && y >= GAME_TOP && y <= SCREEN_H - 2 )) ; then
        _fi=$(( (y - 1) * FB_W + (x - 1) ))
        if (( FB_OWNER[_fi] == _ticket )) ; then
            FB_CELL[_fi]='' FB_OWNER[_fi]=0 FB_DIRTY+=("$_fi")
        fi
    fi
    EB_ALIVE[i]=0 EB_GLYPH[i]=''
    EB_FREE+=("$i")
    (( EB_LIVE-- ))
    return 0
}

# 兼容老调用点：enemy_bullet_spawn <Cls> <args...>
#   EnemyBullet  x y sym dmg
#   BossBullet   x y vx vy sym dmg step color
#   EnemyMissile x y fuel step
enemy_bullet_spawn () {
    local cls=$1
    case "$cls" in
    EnemyBullet)
        eb_add 0 "$2" "$3" 0 1 4 0 "${5:-1}" "${4}$C_RESET" 0 ;;
    BossBullet)
        local -i _step=${8:-2}
        (( _step < 1 )) && _step=1
        eb_add 1 "$2" "$3" "${4:-0}" "${5:-1}" "$_step" 0 "${7:-1}" "${9:-}${6}$C_RESET" 0 ;;
    EnemyMissile)
        eb_add 2 "$2" "$3" 0 1 "${5:-$BOSS_BUFF_MISSILE_STEP}" 0 1 \
               "${C_BOLD}${C_RED}${BOSS_BUFF_MISSILE_SYM}$C_RESET" "${4:-$BOSS_BUFF_MISSILE_FUEL}" ;;
    *)
        return 1 ;;
    esac
}

# 测试/工具用：读槽位字段
eb_field () {
    case "$2" in
    x) REPLY=${EB_X[$1]} ;;
    y) REPLY=${EB_Y[$1]} ;;
    damage) REPLY=${EB_DMG[$1]} ;;
    symbol) REPLY=${EB_GLYPH[$1]} ;;
    type) REPLY=${EB_TYPE[$1]} ;;
    fuel) REPLY=${EB_FUEL[$1]} ;;
    step) REPLY=${EB_STEP[$1]} ;;
    alive) REPLY=${EB_ALIVE[$1]} ;;
    *) REPLY='' ;;
    esac
}

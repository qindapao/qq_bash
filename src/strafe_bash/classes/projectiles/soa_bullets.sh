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
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[soa_bullets]++ )) && return 0
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

# 类型 0 的"相位桶"：出生时 G_RUN_TICKS & 3 决定它每 4 tick 里哪一 tick 移动，
# 桶里只放槽号；同 tick 的处理由 play_game 负责。类型 1/2 进 EB_VAR 小表。
declare -gai EB_PHASE=() EB_SEEN=()
declare -ga  EB_BK0=() EB_BK1=() EB_BK2=() EB_BK3=() EB_VAR=()

# 新局/读档：全部清空
eb_reset () {
    EB_ALIVE=() EB_TYPE=() EB_X=() EB_Y=() EB_VX=() EB_VY=() \
    EB_STEP=() EB_CD=() EB_DMG=() EB_FUEL=() EB_GLYPH=() EB_TAG=() EB_FREE=() \
    EB_PHASE=() EB_SEEN=() EB_BK0=() EB_BK1=() EB_BK2=() EB_BK3=() EB_VAR=()
    EB_N=0 EB_LIVE=0
    return 0
}

# 出生：取一个槽（优先空闲栈），写字段并占格
# $1=type $2=x $3=y $4=vx $5=vy $6=step $7=cd $8=damage $9=glyph $10=fuel
eb_add () {
    # 出生坐标夹到可玩区：Boss 的巨型弹幕 pattern 是 cy±6 的偏移，
    # Boss 停在顶部时 cy=7，偏移 -6 就会算到第 1 行（边框）。
    # 不夹的话子弹会画进 HUD/边框的格子，等它死亡清格时又把边框擦出缺口。
    local -i i _sx=${2:-0} _sy=${3:-0}
    (( _sx < 2 )) && _sx=2
    (( _sx > SCREEN_W - 2 )) && _sx=$(( SCREEN_W - 2 ))
    (( _sy < GAME_TOP )) && _sy=$GAME_TOP
    (( _sy > SCREEN_H - 2 )) && _sy=$(( SCREEN_H - 2 ))
    if (( ${#EB_FREE[@]} )) ; then
        i=${EB_FREE[-1]}
        unset 'EB_FREE[-1]'
    else
        (( EB_N >= ENEMY_BULLET_LIMIT )) && return 1
        i=$EB_N
        (( EB_N++ ))
    fi
    EB_ALIVE[i]=1 EB_TYPE[i]=$1 EB_X[i]=$_sx EB_Y[i]=$_sy EB_VX[i]=$4 EB_VY[i]=$5 \
    EB_STEP[i]=$6 EB_CD[i]=$7 EB_DMG[i]=$8 EB_GLYPH[i]=$9 EB_FUEL[i]=${10:-0} \
    EB_TAG[i]="E$i" EB_SEEN[i]=-1
    if (( $1 == 0 )) ; then
        local -i _ph=$(( G_RUN_TICKS & 3 ))
        EB_PHASE[i]=$_ph
        local -n _bkt="EB_BK$_ph"
        _bkt+=("$i")
    else
        EB_VAR+=("$i")
    fi
    (( EB_LIVE++ ))
    local -i _fi=$(( (_sy - 1) * FB_W + (_sx - 1) ))
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

# 测试/工具用：让一发直下弹（type 0）在下一个 tick 移动。
# 正常节奏由出生相位决定；这个入口只给"必须在本 tick 看到它动"的用例使用。
# 注意相位取 G_RUN_TICKS+1：本函数在 tick 之间调用，下一个 tick 的桶号才是它。
eb_force_move_now () {
    local -i i=$1
    (( EB_ALIVE[i] )) || return 1
    (( EB_TYPE[i] == 0 )) || return 1
    local -i _ph=$(( (G_RUN_TICKS + 1) & 3 ))
    EB_PHASE[i]=$_ph
    local -n _bkt="EB_BK$_ph"
    _bkt+=("$i")
    return 0
}

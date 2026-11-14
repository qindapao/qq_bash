# classes/enemies/boss.sh — Boss
[[ -n "${_STRAFE_BOSS_SH:-}" ]] && return 0
_STRAFE_BOSS_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/art.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/enemy_bullet.sh"

readonly BossStaticTemplate='
    BossObj ->
        {CLS} => Boss
        {SUP} => Entity
        {MIX} => 
        {x} => 0
        {y} => 0
        {w} => 13
        {h} => 5
        {art} => 
        {hp} => 150
        {maxhp} => 150
        {score} => 5000
        {cd} => 0
        {symbol} => X
        {phase} => 0
        {tx} => 0
        {ty} => 0
        {ttl} => 0
    '
Boss_born () {
    local -n self=$1
    local _bx=$(( (SCREEN_W - 13) / 2 ))
    self["{x}$X"]=$_bx
    self["{y}$X"]=$GAME_TOP
    self["{cd}$X"]=0
    self["{phase}$X"]=0
    self["{art}$X"]="$BOSS_ART_100"
    self["{tx}$X"]=$_bx
    self["{ty}$X"]=$GAME_TOP
    self["{ttl}$X"]=0
}
Boss_move () {
    local -n self=$1

    local _hp=${self["{hp}$X"]} _maxhp=${self["{maxhp}$X"]}
    local _pct=$(( _hp * 100 / _maxhp ))
    local _newphase
    if (( _pct > 70 )) ; then _newphase=0
    elif (( _pct > 50 )) ; then _newphase=1
    elif (( _pct > 20 )) ; then _newphase=2
    else _newphase=3
    fi
    if (( _newphase != ${self["{phase}$X"]} )) ; then
        self["{phase}$X"]=$_newphase
        case "$_newphase" in
            0) self["{art}$X"]="$BOSS_ART_100" ;;
            1) self["{art}$X"]="$BOSS_ART_70" ;;
            2) self["{art}$X"]="$BOSS_ART_50" ;;
            3) self["{art}$X"]="$BOSS_ART_20" ;;
        esac
        self["{ttl}$X"]=0        # 阶段变化立即换一条轨迹
    fi

    # 目标点移动：每 _step 个 tick 朝 (tx,ty) 走一格。
    # 到达 / ttl 到期 / 小概率中途变向时重新选目标。
    # 越到后面阶段，移动越快、纵向范围越大。
    local cd=$(( ${self["{cd}$X"]} + 1 ))
    local -i _step=4
    (( _newphase == 2 )) && _step=3
    (( _newphase == 3 )) && _step=2
    if (( cd >= _step )) ; then
        self["{cd}$X"]=0

        local -i _w=${self["{w}$X"]} _h=${self["{h}$X"]}
        local -i _xmin=2 _xmax=$(( SCREEN_W - 2 - _w ))
        # y 上限留出 HP 条那一行，避免 Boss 的 [K 清行擦掉玩家
        local -i _ymin=$GAME_TOP _ymax=$(( SCREEN_H - 4 - _h ))
        (( _xmax < _xmin )) && _xmax=$_xmin
        (( _ymax < _ymin )) && _ymax=$_ymin

        local -i x=${self["{x}$X"]} y=${self["{y}$X"]}
        local -i tx=${self["{tx}$X"]} ty=${self["{ty}$X"]} ttl=${self["{ttl}$X"]}

        # 防御性 clamp：窗口过小或坐标异常时把 Boss 拉回有效范围
        (( x < _xmin )) && x=$_xmin
        (( x > _xmax )) && x=$_xmax
        (( y < _ymin )) && y=$_ymin
        (( y > _ymax )) && y=$_ymax

        if (( ttl <= 0 || (x == tx && y == ty) )) || (( RANDOM % 100 < 7 )) ; then
            local -i _hi=$_ymax
            case "$_newphase" in
                0) _hi=$(( _ymin + 6 )) ;;
                1) _hi=$(( _ymin + (_ymax - _ymin) * 3 / 4 )) ;;
            esac
            (( _hi > _ymax )) && _hi=$_ymax
            (( _hi < _ymin )) && _hi=$_ymin
            tx=$(( RANDOM % (_xmax - _xmin + 1) + _xmin ))
            ty=$(( RANDOM % (_hi - _ymin + 1) + _ymin ))
            ttl=$(( 8 + RANDOM % 9 ))
        else
            (( ttl-- ))
        fi

        if (( x < tx )) ; then x=$(( x + 1 ))
        elif (( x > tx )) ; then x=$(( x - 1 )) ; fi
        if (( y < ty )) ; then y=$(( y + 1 ))
        elif (( y > ty )) ; then y=$(( y - 1 )) ; fi

        (( x < _xmin )) && x=$_xmin
        (( x > _xmax )) && x=$_xmax
        (( y < _ymin )) && y=$_ymin
        (( y > _ymax )) && y=$_ymax

        self["{x}$X"]=$x ; self["{y}$X"]=$y
        self["{tx}$X"]=$tx ; self["{ty}$X"]=$ty ; self["{ttl}$X"]=$ttl
    else
        self["{cd}$X"]=$cd
    fi

    # Boss 永不主动离场，只会被打死；这里只有开火逻辑
    (( RANDOM % 100 < 8 )) || return 0
    local _by=$(( ${self["{y}$X"]} + ${self["{h}$X"]} ))
    local _bx=${self["{x}$X"]}
    xo_obj_born EnemyBullet $((_bx + 4)) "$_by" '!' 3
    ENEMY_BULLETS+=("$REPLY")
    xo_obj_born EnemyBullet $((_bx + 6)) "$_by" '0' 3
    ENEMY_BULLETS+=("$REPLY")
    xo_obj_born EnemyBullet $((_bx + 8)) "$_by" '!' 3
    ENEMY_BULLETS+=("$REPLY")
    return 0
}

# classes/enemies/boss_pattern.sh — 共享的“单发子弹拼巨型弹幕”时序
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[boss_pattern]++ )) && return 0
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/color.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/soa_bullets.sh"

# 每项：dx|dy|vx|vy|symbol
# 方向不是固定的：前段向中心收，中段垂直，后段向外翻。
readonly -a BOSS_AIM_PATTERN_STEPS=(
    '-11|-5|1|1|o'
    '-10|-4|1|1|x'
    '-9|-3|1|1|o'
    '-8|-2|0|1|x'
    '-7|-1|0|1|o'
    '-6|0|0|1|x'
    '-5|1|0|1|o'
    '-4|2|-1|1|x'
    '-3|3|-1|1|o'
    '-2|4|-1|1|x'
    '-1|5|-1|1|o'
    '0|6|-1|1|x'
)

# 根据玩家相对位置，决定整条弹幕朝哪个象限旋转。
_boss_pattern_mode () {
    local -n _bp=$1
    local -i cx=$(( ${_bp[x]} + ${_bp[w]} / 2 )) \
             cy=$(( ${_bp[y]} + ${_bp[h]} / 2 ))
    if [[ -z "${XO_OBJ_POOL[OBJ_player]+_}" ]] ; then REPLY=0 ; return 0 ; fi
    local -i dx=$(( ${OBJ_player[x]} - cx )) \
             dy=$(( ${OBJ_player[y]} - cy ))
    local -i ax=$dx ay=$dy
    (( ax < 0 )) && ax=$(( -ax ))
    (( ay < 0 )) && ay=$(( -ay ))
    if (( ax > ay )) ; then
        (( dx > 0 )) && REPLY=1 || REPLY=3
    else
        (( dy > 0 )) && REPLY=0 || REPLY=2
    fi
}

# $1=obj $2=step $3=mode $4=speed
_boss_pattern_spawn_step () {
    local -n _bp=$1
    local -i _step=$2 _mode=$3 _speed=${4:-4} \
             cx=$(( ${_bp[x]} + ${_bp[w]} / 2 )) \
             cy=$(( ${_bp[y]} + ${_bp[h]} / 2 ))
    (( EB_LIVE + 2 > ENEMY_BULLET_LIMIT )) && return 0

    local _entry=${BOSS_AIM_PATTERN_STEPS[_step]}
    local _dx _dy _vx _vy _sym
    IFS='|' read -r _dx _dy _vx _vy _sym <<< "$_entry"

    local -i _side _ldx _ldy _lvx _lvy _wx _wy _wvx _wvy
    for _side in 0 1 ; do
        _ldx=$_dx ; _ldy=$_dy ; _lvx=$_vx ; _lvy=$_vy
        if (( _side )) ; then
            _ldx=$(( -_ldx )) ; _lvx=$(( -_lvx ))
        fi
        case "$_mode" in
            0) _wx=$_ldx ; _wy=$_ldy   ; _wvx=$_lvx ; _wvy=$_lvy ;;
            1) _wx=$_ldy ; _wy=$(( -_ldx )) ; _wvx=$_lvy ; _wvy=$(( -_lvx )) ;;
            2) _wx=$(( -_ldx )) ; _wy=$(( -_ldy )) ; _wvx=$(( -_lvx )) ; _wvy=$(( -_lvy )) ;;
            3) _wx=$(( -_ldy )) ; _wy=$_ldx ; _wvx=$(( -_lvy )) ; _wvy=$_lvx ;;
            *) _wx=$_ldx ; _wy=$_ldy ; _wvx=$_lvx ; _wvy=$_lvy ;;
        esac
        if (( _side == 0 )) ; then
            enemy_bullet_spawn BossBullet "$(( cx + _wx ))" "$(( cy + _wy ))" "$_wvx" "$_wvy" "$_sym" 3 "$_speed" "$C_CYAN"
        else
            enemy_bullet_spawn BossBullet "$(( cx + _wx ))" "$(( cy + _wy ))" "$_wvx" "$_wvy" "$_sym" 3 "$_speed" "$C_ORANGE"
        fi
    done
}

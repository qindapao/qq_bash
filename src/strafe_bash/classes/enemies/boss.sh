# classes/enemies/boss.sh — Boss（标准 Boss，继承 BossBase）
[[ -n "${_STRAFE_BOSS_SH:-}" ]] && return 0
_STRAFE_BOSS_SH=1
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/classes/base_types.sh"
. "$STRAFE_PROJ_DIR/classes/enemies/boss_base.sh"
. "$STRAFE_PROJ_DIR/config/const.sh"
. "$STRAFE_PROJ_DIR/config/globals.sh"
. "$STRAFE_PROJ_DIR/classes/projectiles/enemy_bullet.sh"

# 标准 Boss 的四段 art。放在类文件里，Boss_move 只认字段，不再写死变量名。
readonly BOSS_ART_100=$'    _____    \n   /     \\   \n  /  O O  \\  \n  \\_|_|_|_/  \n   \\_____/   '
readonly BOSS_ART_70=$'    _____    \n   /     \\   \n  /  X O  \\  \n  \\_|_|_._/  \n   \\_____/   '
readonly BOSS_ART_50=$'    _____    \n   /     \\   \n  /  X X  \\  \n  \\_._|_._/  \n   \\_____/   '
readonly BOSS_ART_20=$'    _____    \n   /     \\   \n  /  x X  \\  \n  \\_._._._/  \n   \\_____/   '

readonly BossStaticTemplate='
    BossObj ->
        {CLS} => Boss
        {SUP} => BossBase
        {MIX} => 
        {name} => THE CLASSIC BOSS
        {w} => 13
        {h} => 5
        {hp} => 150
        {maxhp} => 150
        {score} => 5000
        {symbol} => X
        {pcut1} => 70
        {pcut2} => 50
        {pcut3} => 20
        {death_style} => 0
    '
Boss_born () {
    _boss_set_arts "$1" "$BOSS_ART_100" "$BOSS_ART_70" "$BOSS_ART_50" "$BOSS_ART_20"
    BossBase_born "$1"
}
Boss_move () {
    _boss_update_phase "$1"
    local -n self=$1

    local -i _phase=${self["{phase}$X"]}
    local -i _step=4
    (( _phase == 2 )) && _step=3
    (( _phase == 3 )) && _step=2

    local -i _ymin=$GAME_TOP
    local -i _ymax=$(( SCREEN_H - 4 - ${self["{h}$X"]} ))
    local -i _yhi=$_ymax
    case "$_phase" in
        0) _yhi=$(( _ymin + 6 )) ;;
        1) _yhi=$(( _ymin + (_ymax - _ymin) * 3 / 4 )) ;;
    esac
    _boss_move_target "$1" "$_step" "$_yhi" 7 8 9

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

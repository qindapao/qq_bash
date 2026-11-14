# classes/plane/plane_types.sh — 四种可选机型
[[ -n "${_STRAFE_PLANE_TYPES_SH:-}" ]] && return 0
_STRAFE_PLANE_TYPES_SH=1
. "$STRAFE_PROJ_DIR/classes/plane/plane.sh"

# Bee: inherits the default Plane values
readonly PlaneBeeStaticTemplate='
    PlaneBeeObj ->
        {CLS} => PlaneBee
        {SUP} => Plane
        {MIX} => 
    '

# Hornet: 30 HP, 60% kill score
readonly PlaneHornetStaticTemplate='
    PlaneHornetObj ->
        {CLS} => PlaneHornet
        {SUP} => Plane
        {MIX} => 
        {w} => 5
        {h} => 2
        {al} => 2
        {base_al} => 2
        {shield_al} => 4
        {shield_w} => 9
        {shield_h} => 3
        {shield_top} => -1
        {maxhp} => 30
        {score_pct} => 60
    '

# Eagle-1: 15 HP, non-laser bullets +1 speed
readonly PlaneEagleStaticTemplate='
    PlaneEagleObj ->
        {CLS} => PlaneEagle
        {SUP} => Plane
        {MIX} => 
        {w} => 5
        {h} => 2
        {al} => 2
        {base_al} => 2
        {shield_al} => 4
        {shield_w} => 9
        {shield_h} => 3
        {shield_top} => -1
        {maxhp} => 15
        {spd_delta} => 1
        {laser_exempt} => 1
    '

# Il-2: 40 HP, all bullets -1 speed
readonly PlaneIl2StaticTemplate='
    PlaneIl2Obj ->
        {CLS} => PlaneIl2
        {SUP} => Plane
        {MIX} => M_LongBlink M_Blink M_Ram
        {w} => 5
        {h} => 2
        {al} => 2
        {base_al} => 2
        {shield_al} => 4
        {shield_w} => 9
        {shield_h} => 3
        {shield_top} => -1
        {maxhp} => 40
        {spd_delta} => -1
    '

# 给选机界面/存档用的固定顺序
declare -a PLANE_CLASSES=(PlaneBee PlaneHornet PlaneEagle PlaneIl2)

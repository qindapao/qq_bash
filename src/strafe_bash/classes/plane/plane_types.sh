# classes/plane/plane_types.sh — 四种可选机型
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[plane_types]++ )) && return 0
. "$STRAFE_PROJ_DIR/classes/plane/plane.sh"


# 类变量和方法声明
declare -gA XO_CLASS_FLAT_OBJ_VARS XO_CLASS_METHODS
XO_CLASS_FLAT_OBJ_VARS[PlaneBeeObj]=1
XO_CLASS_METHODS[PlaneBee]=''
XO_CLASS_FLAT_OBJ_VARS[PlaneHornetObj]=1
XO_CLASS_METHODS[PlaneHornet]=''
XO_CLASS_FLAT_OBJ_VARS[PlaneEagleObj]=1
XO_CLASS_METHODS[PlaneEagle]=''
XO_CLASS_FLAT_OBJ_VARS[PlaneIl2Obj]=1
XO_CLASS_METHODS[PlaneIl2]=''

# Bee: inherits the default Plane values
# 字段含义全部继承自 Plane，这里一个都没覆盖
declare -gA PlaneBeeObj=(
    [{CLS}$X]='PlaneBee'
    [{SUP}$X]='Plane'
    [{MIX}$X]=''
)

# Hornet: 30 HP, 60% kill score
# 只覆盖外形与数值：w/h=机体包围盒，al 系列=立绘居中余量，
# shield_* = 护盾包围盒，maxhp=30 血，score_pct=60（击杀得分打六折）
declare -gA PlaneHornetObj=(
    [{CLS}$X]='PlaneHornet'
    [{SUP}$X]='Plane'
    [{MIX}$X]=''
    [w]='5'
    [h]='2'
    [al]='2'
    [base_al]='2'
    [shield_al]='4'
    [shield_w]='9'
    [shield_h]='3'
    [shield_top]='-1'
    [maxhp]='30'
    [score_pct]='60'
)

# Eagle-1: 15 HP, non-laser bullets +1 speed
# 数值差异：maxhp=15（脆），spd_delta=+1（子弹更快），cd_delta=-1（射速更快），
# laser_exempt=1（激光不享受弹速加成，保持能量武器自己的手感）
declare -gA PlaneEagleObj=(
    [{CLS}$X]='PlaneEagle'
    [{SUP}$X]='Plane'
    [{MIX}$X]=''
    [w]='5'
    [h]='2'
    [al]='2'
    [base_al]='2'
    [shield_al]='4'
    [shield_w]='9'
    [shield_h]='3'
    [shield_top]='-1'
    [maxhp]='15'
    [spd_delta]='1'
    [cd_delta]='-1'
    [laser_exempt]='1'
)

# Il-2: 40 HP, all bullets -1 speed
# 数值差异：maxhp=40（最厚），spd_delta=-1（子弹更慢）；
# MIX 额外挂 M_LongBlink（受伤无敌 4 秒）与 M_Ram（撞击伤害）
declare -gA PlaneIl2Obj=(
    [{CLS}$X]='PlaneIl2'
    [{SUP}$X]='Plane'
    [{MIX}$X]='M_LongBlink M_Blink M_Ram'
    [w]='5'
    [h]='2'
    [al]='2'
    [base_al]='2'
    [shield_al]='4'
    [shield_w]='9'
    [shield_h]='3'
    [shield_top]='-1'
    [maxhp]='40'
    [spd_delta]='-1'
)

# 给选机界面/存档用的固定顺序
declare -a PLANE_CLASSES=(PlaneBee PlaneHornet PlaneEagle PlaneIl2)

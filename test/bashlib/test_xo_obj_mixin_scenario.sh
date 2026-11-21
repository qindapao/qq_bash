#!/usr/bin/env bash
#
# 对象级 Mixin 综合场景测试。
#
# 和 test_xo_obj_mixin.sh（逐条单测）的区别：这里是一个连续的"真实使用"流程，
# 类层级、类级 {MIX}、对象级 {OBJMIX} 三者混在一起跑，逐阶段断言。
#
# 被验证的语义（每条都有对应断言）：
#   1. 没有动态能力时，xo_obj_call 与 xo_call 等价（回落类方法、继承方法）
#   2. 对象级能力只影响该对象，别的对象不受影响
#   3. 对象级能力盖过类自身方法、继承方法、以及类级 {MIX} 注入的方法
#   4. 同名方法"先加先赢"，删除后按名单顺序回退，接任者再被删则继续往后回退
#   5. 重新注入会排到名单末尾，因此不恢复原先的优先级
#   6. 私有方法（M_Xxx__foo）不会被注入
#   7. 类模板未声明 {OBJMIX} 时 add 被拒绝（契约守卫）
#   8. 具名句柄 bury 后重建，残留路由被清理
#   9. 删不存在的 Mixin、全卸载、多对象并存
#  10. 混入方法集合在首次使用时固定（与 xo_init 类级注入的时机一致）

. ../../src/bashlib/xo.sh
. ../libs/test_utils.sh

CHECKS=0
FAILS=0

check ()        # $1=标签 $2=期望 $3=实际
{
    CHECKS=$((CHECKS+1))
    if [[ "$2" == "$3" ]] ; then
        printf '  [ok]   %-46s %s\n' "$1" "$3"
    else
        printf '  [FAIL] %-46s 期望=[%s] 实际=[%s]\n' "$1" "$2" "$3"
        FAILS=$((FAILS+1))
    fi
}

expect_fail ()  # $1=标签 $2..=命令：期望调用失败
{
    CHECKS=$((CHECKS+1))
    if "$@" >/dev/null 2>&1 ; then
        printf '  [FAIL] %-46s 期望失败但成功了\n' "$1"
        FAILS=$((FAILS+1))
    else
        printf '  [ok]   %-46s 调用失败（符合预期）\n' "$1"
    fi
}

# 调一次并把 REPLY 打出来，便于放进 check 的 $3。
# 必须先清空 REPLY：调用失败时（命令不存在）REPLY 会保留上一次的值，导致断言读到脏数据。
r () { REPLY='' ; "$@" >/dev/null 2>&1 ; printf '%s' "$REPLY" ; }

# ---------------------------------------------------------------------------
# 类方法（手写）与类级 Mixin
# ---------------------------------------------------------------------------
Mob_act () { REPLY='mob' ; }
Mob_health () { REPLY='100' ; }
Mob_absorb () { REPLY='mob-absorb' ; }        # 先手写一个，验证"类自身 > 类级 Mixin"

Boss_act () { REPLY='boss' ; }                # Boss 覆盖 Mob_act

M_Shield_absorb () { REPLY='shield' ; }       # 类级 {MIX}：只给 Mob 注入

# ---------------------------------------------------------------------------
# 对象级 Mixin
# ---------------------------------------------------------------------------
M_Fire_act () { REPLY='fire' ; }
M_Fire_tick () { REPLY='fire' ; }
M_Fire__secret () { REPLY='secret' ; }        # 双下划线：私有，不得注入

M_Ice_tick () { REPLY='ice' ; }
M_Ice_freeze () { REPLY='ice' ; }
M_Ice_health () { REPLY='ice-hp' ; }

M_Wind_tick () { REPLY='wind' ; }

M_Absorb_absorb () { REPLY='objabsorb' ; }

# Mob 声明 {OBJMIX}（行尾空格是模板空值写法）；Boss 故意不声明，
# 用来验证「声明会随类对象继承下去」。
declare -gA EntityObj=(
    [{CLS}$X]='Entity'
    [{SUP}$X]='Base'
)
declare -gA MobObj=(
    [{CLS}$X]='Mob'
    [{SUP}$X]='Entity'
    [{MIX}$X]='M_Shield'
    [{OBJMIX}$X]=''
)
declare -gA BossObj=(
    [{CLS}$X]='Boss'
    [{SUP}$X]='Mob'
)

# 手工注册表契约：类对象、类方法、对象级 Mixin 都必须显式登记。
XO_CLASS_FLAT_OBJ_VARS[EntityObj]=1
XO_CLASS_METHODS[Entity]=''
XO_CLASS_FLAT_OBJ_VARS[MobObj]=1
XO_CLASS_METHODS[Mob]='act health absorb'
XO_CLASS_FLAT_OBJ_VARS[BossObj]=1
XO_CLASS_METHODS[Boss]='act'
XO_MIXIN_METHODS[M_Shield]='absorb'
XO_MIXIN_METHODS[M_Fire]='act tick'
XO_MIXIN_METHODS[M_Ice]='tick freeze health'
XO_MIXIN_METHODS[M_Wind]='tick'
XO_MIXIN_METHODS[M_Absorb]='absorb'

xo_init

test_case1 ()
{
    printf '\n== 阶段 1：没有动态能力时，与 xo_call 等价 ==\n'
    xo_obj_born_named OBJ_b1 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    xo_obj_born_named OBJ_b2 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }

    check '对象方法（Boss 覆盖 Mob）' 'boss' "$(r xo_obj_call OBJ_b1 act)"
    check '继承方法（Mob_health 透传到 Boss）' '100' "$(r xo_obj_call OBJ_b1 health)"
    check '类级 {MIX} 注入的方法（absorb）' 'shield' "$(r xo_obj_call OBJ_b1 absorb)"

    # 优先级：类自身方法 > Mixin 方法 > 继承透传
    xo_obj_born_named OBJ_m Mob >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    check 'Mob 实例：自身手写 absorb 压过 Mixin' 'mob-absorb' "$(r xo_call OBJ_m absorb)"
    # Boss 没写 absorb，但它从 Mob 的类对象继承了 {MIX}，所以这一层 Mixin 赢过 Mob 的实现
    check 'Boss 实例：继承来的 {MIX} 压过父类实现' 'shield' "$(r xo_call OBJ_b1 absorb)"
    check '{OBJMIX} 初始为空' '' "$(r xo_obj_mixin_list OBJ_b1)"

    printf '\n== 阶段 2：注入只影响本对象，并盖过类方法 ==\n'
    xo_obj_mixin_add OBJ_b1 M_Fire
    check 'b1 的 act 被对象级 Mixin 接管' 'fire' "$(r xo_obj_call OBJ_b1 act)"
    check 'b1 的 tick 来自 M_Fire' 'fire' "$(r xo_obj_call OBJ_b1 tick)"
    check 'b2 未受影响（仍是类方法）' 'boss' "$(r xo_obj_call OBJ_b2 act)"
    check 'b2 没有 tick' '' "$(r xo_obj_call OBJ_b2 tick)"
    check 'b1 名单只有 M_Fire（无前后空格）' 'M_Fire' "$(r xo_obj_mixin_list OBJ_b1)"
    expect_fail '私有方法 M_Fire__secret 未被注入' xo_obj_call OBJ_b1 secret

    printf '\n== 阶段 3：多 Mixin 同名方法（先加先赢）+ 独有能力 ==\n'
    xo_obj_mixin_add OBJ_b1 M_Ice
    check 'tick 仍由最先的 M_Fire 提供' 'fire' "$(r xo_obj_call OBJ_b1 tick)"
    check 'M_Ice 独有方法 freeze 可用' 'ice' "$(r xo_obj_call OBJ_b1 freeze)"
    check 'M_Ice 的 health 盖过继承方法' 'ice-hp' "$(r xo_obj_call OBJ_b1 health)"
    check '名单格式（单空格分隔）' 'M_Fire M_Ice' "$(r xo_obj_mixin_list OBJ_b1)"

    xo_obj_mixin_add OBJ_b1 M_Wind
    check '三方同名 tick 仍由最先的 M_Fire 提供' 'fire' "$(r xo_obj_call OBJ_b1 tick)"

    printf '\n== 阶段 4：删最先的 M_Fire，各方法分别回退 ==\n'
    xo_obj_mixin_delete OBJ_b1 M_Fire
    check 'tick 回退给 M_Ice' 'ice' "$(r xo_obj_call OBJ_b1 tick)"
    check 'act 不再有人提供 → 回落类方法' 'boss' "$(r xo_obj_call OBJ_b1 act)"
    check 'health 仍由 M_Ice 提供' 'ice-hp' "$(r xo_obj_call OBJ_b1 health)"
    check '名单只剩 M_Ice M_Wind' 'M_Ice M_Wind' "$(r xo_obj_mixin_list OBJ_b1)"

    printf '\n== 阶段 5：继续删接任者 M_Ice，回退链走到 M_Wind ==\n'
    xo_obj_mixin_delete OBJ_b1 M_Ice
    check 'tick 回退给 M_Wind' 'wind' "$(r xo_obj_call OBJ_b1 tick)"
    expect_fail 'freeze 随 M_Ice 一起消失' xo_obj_call OBJ_b1 freeze
    check 'health 回落继承方法' '100' "$(r xo_obj_call OBJ_b1 health)"
    check '名单只剩 M_Wind' 'M_Wind' "$(r xo_obj_mixin_list OBJ_b1)"

    printf '\n== 阶段 6：重新注入 M_Fire，优先级排到末尾 ==\n'
    xo_obj_mixin_add OBJ_b1 M_Fire
    check 'tick 仍是 M_Wind（重加不抢占）' 'wind' "$(r xo_obj_call OBJ_b1 tick)"
    check 'act 重新可用' 'fire' "$(r xo_obj_call OBJ_b1 act)"
    check '名单顺序反映真实优先级' 'M_Wind M_Fire' "$(r xo_obj_mixin_list OBJ_b1)"

    printf '\n== 阶段 7：对象级 Mixin 盖过类级 Mixin ==\n'
    xo_obj_mixin_add OBJ_b1 M_Absorb
    check 'xo_obj_call 走对象级' 'objabsorb' "$(r xo_obj_call OBJ_b1 absorb)"
    check 'xo_call 仍走类级（两条路径互不干扰）' 'shield' "$(r xo_call OBJ_b1 absorb)"
    xo_obj_mixin_delete OBJ_b1 M_Absorb
    check '卸载对象级后回落到类级 Mixin' 'shield' "$(r xo_obj_call OBJ_b1 absorb)"

    printf '\n== 阶段 8：删不存在的 Mixin 无副作用 ==\n'
    xo_obj_mixin_delete OBJ_b1 M_NoSuchMixin
    check '名单未变' 'M_Wind M_Fire' "$(r xo_obj_mixin_list OBJ_b1)"
    check 'tick 未变' 'wind' "$(r xo_obj_call OBJ_b1 tick)"

    printf '\n== 阶段 9：b2 全程未受影响 ==\n'
    check 'b2 名单为空' '' "$(r xo_obj_mixin_list OBJ_b2)"
    expect_fail 'b2 没有动态能力' xo_obj_call OBJ_b2 tick
    check 'b2 类级 Mixin 仍正常' 'shield' "$(r xo_obj_call OBJ_b2 absorb)"

    printf '\n== 阶段 10：契约守卫（类未声明 {OBJMIX}）==\n'
    xo_obj_born_named OBJ_e Entity >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    expect_fail 'Entity 未声明 {OBJMIX}，add 被拒绝' xo_obj_mixin_add OBJ_e M_Fire
    check '被拒绝后不产生路由' '' "$(r xo_obj_call OBJ_e tick)"

    printf '\n== 阶段 11：bury 后同名句柄重建，残留路由被清理 ==\n'
    xo_obj_bury OBJ_b1 >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    check 'bury 后不再算「持有动态能力」' '' "${XO_OBJ_MIXED[OBJ_b1]-}"
    check 'bury 后该对象的路由全部消失' '' \
        "$(for k in "${!XO_OBJ_METHOD[@]}" ; do [[ "$k" == 'OBJ_b1|'* ]] && printf '%s ' "$k" ; done)"
    xo_obj_born_named OBJ_b1 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    check '重建后名单为空' '' "$(r xo_obj_mixin_list OBJ_b1)"
    check '重建后 act 回到类方法（旧路由未残留）' 'boss' "$(r xo_obj_call OBJ_b1 act)"
    expect_fail '重建后旧 tick 不可用' xo_obj_call OBJ_b1 tick
    xo_obj_mixin_add OBJ_b1 M_Ice
    check '重新注入后 tick 是新的 M_Ice' 'ice' "$(r xo_obj_call OBJ_b1 tick)"

    printf '\n== 阶段 12：混入方法集合在首次使用时固定 ==\n'
    # M_Wind 的方法在阶段 3 首次 add 时已扫描并缓存；此后新增的方法不会被注入。
    # 与 xo_init 时类级注入的时机一致：所有 Mixin 方法都应在 xo_init 之前定义。
    M_Wind_late () { REPLY='late' ; }
    if [[ -n "${XO_OBJ_POOL[OBJ_b3]+_}" ]] ; then xo_obj_bury OBJ_b3 >/dev/null 2>&1 ; fi
    xo_obj_born_named OBJ_b3 Boss >/dev/null 2>&1 || { log_test 0 1 ; return 1 ; }
    xo_obj_mixin_add OBJ_b3 M_Wind
    check 'M_Wind 原有方法可用' 'wind' "$(r xo_obj_call OBJ_b3 tick)"
    expect_fail '首次扫描之后新增的方法不会被注入' xo_obj_call OBJ_b3 late

    printf '\n== 阶段 13：全卸载只影响该对象 ==\n'
    xo_obj_mixin_add OBJ_b3 M_Fire
    xo_obj_mixin_delete OBJ_b3
    check 'b3 名单清空' '' "$(r xo_obj_mixin_list OBJ_b3)"
    expect_fail 'b3 tick 不可用' xo_obj_call OBJ_b3 tick
    check 'b1 不受影响（仍指向 M_Ice）' 'ice' "$(r xo_obj_call OBJ_b1 tick)"

    printf '\n---- 共断言 %d 项，失败 %d 项 ----\n' "$CHECKS" "$FAILS"
    if (( FAILS == 0 )) ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
}

eval -- "$(AS_RUN_TEST_CASES)"

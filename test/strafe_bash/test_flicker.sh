#!/usr/bin/env bash
# 闪烁回归测试（B/M 敌人 + 道具）。
#
# 两个根因：
#   1) 血条行原来用 \033[K 清整行：会把同一行上先画好的其他敌人 art 一起擦掉，
#      下一帧才重画 → B/M 敌人偶发闪烁。现在只清自己的文本段。
#   2) 掉落物被擦后原来只标进 FB_DIRTY（在 art 之前 emit），会被随后的 art 盖住，
#      等它下次移动才回来 → 道具闪烁。现在掉落物标进 FB_TOP（art 之后再 emit）。
STRAFE_PROJ_DIR=$(cd ../../src/strafe_bash && pwd -P)
STRAFE_LIB_HOME=$(cd ../../src/bashlib && pwd -P)
export STRAFE_PROJ_DIR STRAFE_LIB_HOME
. ../libs/test_utils.sh
. "$STRAFE_LIB_HOME/xo.sh"
. "$STRAFE_PROJ_DIR/game/main.sh" >/dev/null 2>&1
xo_init >/dev/null 2>&1

CHECKS=0 FAILS=0
check ()        # $1=标签 $2=期望 $3=实际
{
    CHECKS=$((CHECKS+1))
    if [[ "$2" == "$3" ]] ; then
        log_test 1 1
        printf '  [ok]   %-46s %s\033[0m\n' "$1" "$3"
    else
        FAILS=$((FAILS+1))
        log_test 0 1
        printf '  [FAIL] %-46s 期望=[%s] 实际=[%s]\033[0m\n' "$1" "$2" "$3"
    fi
}

fresh_game ()
{
    local e
    for e in "${ENEMIES[@]}" ; do [[ -n "${XO_OBJ_POOL[$e]+_}" ]] && xo_obj_bury "$e" ; done
    ENEMIES=() BULLETS=() DROPS=() WORDS=() MISSILES=() HIT_FX=()
    [[ -n "${XO_OBJ_POOL[OBJ_player]+_}" ]] && xo_obj_bury OBJ_player
    xo_obj_born_named OBJ_player PlaneBee >/dev/null 2>&1
    init_game >/dev/null 2>&1
    G_INV=99999999
}

# 用最小 ANSI 解析器回放 FRAME_BUF，返回 (row,col) 上最后写入的字符。
# 只处理本项目用到的序列：ESC[r;cH（定位）和 ESC[...m（颜色）。
screen_char_at ()
{
    local want_r=$1 want_c=$2
    local s=$FRAME_BUF i=0 n=${#FRAME_BUF} r=1 c=1 ch found=''
    while (( i < n )) ; do
        ch=${s:i:1}
        if [[ "$ch" == $'\033' && "${s:i+1:1}" == '[' ]] ; then
            local rest=${s:i+2}
            # 取到终止字母前的内容
            local body=${rest%%[A-Za-z]*}
            local term=${rest:${#body}:1}
            if [[ "$term" == 'H' ]] ; then
                if [[ "$body" == *';'* ]] ; then
                    r=${body%%;*} c=${body#*;}
                elif [[ -n "$body" ]] ; then
                    r=$body c=1
                else
                    r=1 c=1
                fi
            fi
            i=$(( i + 2 + ${#body} + 1 ))
        else
            if (( r == want_r && c == want_c )) ; then found=$ch ; fi
            ((c++))
            i=$((i+1))
        fi
    done
    REPLY=$found
}

printf '\n== 血条行不能擦掉同行的其他敌人 art ==\n'
fresh_game
xo_obj_born EnemyB >/dev/null 2>&1 ; b1=$REPLY
declare -n _e1=$b1
_e1[x]=20 _e1[y]=10
unset -n _e1
xo_obj_born EnemyB >/dev/null 2>&1 ; b2=$REPLY
declare -n _e2=$b2
_e2[x]=60 _e2[y]=13
unset -n _e2
ENEMIES=("$b1" "$b2")
FRAME_BUF=''
render

screen_char_at 13 62
check '血条行右侧的第二只敌人 art 仍在' '_' "$REPLY"
screen_char_at 13 20
check '血条行的 HP 文本已写出' '[' "$REPLY"
screen_char_at 10 21
check '第一只敌人的 art 已画出' '_' "$REPLY"

printf '\n== 被擦后重标脏：掉落进顶层、子弹进 DIRTY ==\n'
fresh_game
xo_obj_born Drop 1 30 20 >/dev/null 2>&1 ; d=$REPLY
idx=$(( (20 - 1) * FB_W + (30 - 1) ))
FB_TOP=() ; FB_DIRTY=()
_fb_touch_cell 20 30
found_top=0 ; for i in "${FB_TOP[@]}" ; do [[ "$i" == "$idx" ]] && found_top=1 ; done
found_dirty=0 ; for i in "${FB_DIRTY[@]}" ; do [[ "$i" == "$idx" ]] && found_dirty=1 ; done
check '掉落格进入 FB_TOP' 1 "$found_top"
check '掉落格不进入 FB_DIRTY' 0 "$found_dirty"

xo_obj_hire Bullet 30 22 '|' 1 0 -1 >/dev/null 2>&1 ; b=$REPLY
idx=$(( (22 - 1) * FB_W + (30 - 1) ))
FB_TOP=() ; FB_DIRTY=()
_fb_touch_cell 22 30
found_top=0 ; for i in "${FB_TOP[@]}" ; do [[ "$i" == "$idx" ]] && found_top=1 ; done
found_dirty=0 ; for i in "${FB_DIRTY[@]}" ; do [[ "$i" == "$idx" ]] && found_dirty=1 ; done
check '子弹格进入 FB_DIRTY' 1 "$found_dirty"
check '子弹格不进入 FB_TOP' 0 "$found_top"

# 擦除补脏函数也必须把掉落物送进顶层
fresh_game
xo_obj_born Drop 1 30 20 >/dev/null 2>&1 ; d=$REPLY
DROPS=("$d")
idx=$(( (20 - 1) * FB_W + (30 - 1) ))
FB_TOP=() ; FB_DIRTY=()
_ER_MIN=([20]=30) _ER_MAX=([20]=30) _ER_CELLS=1 _ER_ROWS=1
_scene_erase_refill
found_top=0 ; for i in "${FB_TOP[@]}" ; do [[ "$i" == "$idx" ]] && found_top=1 ; done
found_dirty=0 ; for i in "${FB_DIRTY[@]}" ; do [[ "$i" == "$idx" ]] && found_dirty=1 ; done
check '擦除补脏：掉落格进入 FB_TOP' 1 "$found_top"
check '擦除补脏：掉落格不进 FB_DIRTY' 0 "$found_dirty"

printf '\n== 道具经过敌人时不闪（art 每帧重画会盖住它）==\n'
fresh_game
xo_obj_born EnemyB >/dev/null 2>&1 ; e=$REPLY
declare -n _ee=$e
_ee[x]=20 _ee[y]=10
unset -n _ee
xo_obj_born Drop H 22 11 >/dev/null 2>&1 ; d=$REPLY
DROPS=("$d") ; ENEMIES=("$e")
FRAME_BUF='' ; render
screen_char_at 11 22 ; first=$REPLY
FRAME_BUF='' ; render
screen_char_at 11 22
check '第二帧道具仍画在 art 之上' "$first" "$REPLY"
check '该格是道具字符' 'H' "$REPLY"

printf '\n---- 共断言 %d 项，失败 %d 项 ----\n' "$CHECKS" "$FAILS"
(( FAILS == 0 )) && exit 0 || exit 1

#!/usr/bin/env bash
#
# 帧缓冲（render/fb.sh）的单元测试。
#
# 为什么要测：
#   - 索引换算 (y-1)*W + (x-1) 写错一次，整块画面就错位，而且很难看出来；
#   - fb_emit 必须只输出脏格、输出后清脏表，否则每帧都会重画全屏；
#   - 空串表示"擦成空格"，非空表示"颜色+字符"，两种输出不能混。

STRAFE_PROJ_DIR=$(cd ../../src/strafe_bash && pwd -P)
STRAFE_LIB_HOME=$(cd ../../src/bashlib && pwd -P)
export STRAFE_PROJ_DIR STRAFE_LIB_HOME

. ../libs/test_utils.sh
. "$STRAFE_PROJ_DIR/render/fb.sh"

CHECKS=0
FAILS=0

check ()        # $1=标签 $2=期望 $3=实际
{
    CHECKS=$((CHECKS+1))
    if [[ "$2" == "$3" ]] ; then
        printf '  [ok]   %-44s %s\033[0m\n' "$1" "$3"
    else
        printf '  [FAIL] %-44s 期望=[%s] 实际=[%s]\033[0m\n' "$1" "$2" "$3"
        FAILS=$((FAILS+1))
    fi
}

# ---------------------------------------------------------------------------
# 屏幕比对器：把一帧的 escape 流还原成网格（FRAME_GRID），用来比较
# 「旧渲染器的最终画面」和「帧缓冲的屏幕真值」。
# 只处理本项目会产生的序列：ESC[y;xH、ESC[2J、ESC[K、SGR（忽略）。
# ---------------------------------------------------------------------------
FRAME_GRID=()

fgrid_clear ()
{
    local -i _i
    FRAME_GRID=()
    for (( _i=0 ; _i<FB_N ; _i++ )) ; do FRAME_GRID[_i]=' ' ; done
}

fgrid_parse ()      # $1=完整一帧（先清网格再应用）
{
    fgrid_clear
    fgrid_apply "$1"
}

fgrid_apply ()      # $1=增量（不清网格，接着上一次的状态应用）
{
    local s=$1
    local -i i=0 n=${#s} x=1 y=1 j k
    local c seq final ry rx
    while (( i < n )) ; do
        c=${s:i:1}
        if [[ "$c" == "$ESC" ]] ; then
            j=$(( i + 1 ))
            if (( j < n )) && [[ ${s:j:1} == '[' ]] ; then
                (( j++ ))
                seq=''
                while (( j < n )) ; do
                    c=${s:j:1}
                    [[ "$c" == [0-9\;\?] ]] || break
                    seq+=$c
                    (( j++ ))
                done
                final=${s:j:1}
                case "$final" in
                    H)
                        ry=${seq%%;*} ; rx=${seq#*;}
                        [[ -z "$ry" ]] && ry=1
                        [[ "$seq" == *';'* ]] || rx=1
                        y=$ry ; x=$rx ;;
                    J)
                        fgrid_clear ; y=1 ; x=1 ;;
                    K)
                        k=$(( (y - 1) * FB_W + (x - 1) ))
                        while (( k < y * FB_W )) ; do
                            FRAME_GRID[k]=' ' ; (( k++ ))
                        done ;;
                esac
                i=$(( j + 1 ))
                continue
            fi
        fi
        if [[ "$c" == $'\n' ]] ; then
            (( y++ )) ; x=1 ; (( i++ )) ; continue
        fi
        if (( y >= 1 && y <= FB_H && x >= 1 && x <= FB_W )) ; then
            FRAME_GRID[$(( (y - 1) * FB_W + (x - 1) ))]=$c
        fi
        (( x++ ))
        (( i++ ))
    done
}

fgrid_at ()         # $1=行 $2=列 -> 该格字符
{
    printf '%s' "${FRAME_GRID[$(( ($1 - 1) * FB_W + ($2 - 1) ))]}"
}

fgrid_diff_count () # 统计与 FB_CELL 不一致的格子数（空格和空串视为相同）
{
    local -i _i _n=0
    local a b
    for (( _i=0 ; _i<FB_N ; _i++ )) ; do
        a=${FB_CELL[_i]}
        [[ -z "$a" ]] && a=' '
        b=${FRAME_GRID[_i]}
        [[ "$a" != "$b" ]] && _n=$(( _n + 1 ))
    done
    printf '%s' "$_n"
}

test_case1 ()
{
    printf '\n== 初始化 ==\n'

    fb_init 10 5
    check '宽' 10 "$FB_W"
    check '高' 5 "$FB_H"
    check '格子总数' 50 "$FB_N"
    local -i _empty=1 _k
    for (( _k=0 ; _k<FB_N ; _k++ )) ; do
        [[ -n "${FB_CELL[_k]}" ]] && _empty=0
    done
    check '初始全空' 1 "$_empty"
    check '初始脏表为空' 0 "${#FB_DIRTY[@]}"

    # 索引换算抽查：(3,4) -> (3-1)*10 + (4-1) = 23
    fb_put 3 4 'X'
    check '索引 (3,4) = 23' 'X' "${FB_CELL[23]}"
    check '脏表 1 格' 1 "${#FB_DIRTY[@]}"
    check '脏表记的是 23' 23 "${FB_DIRTY[0]}"
}

test_case2 ()
{
    printf '\n== 输出与清脏 ==\n'

    fb_init 10 5
    FRAME_BUF=''
    fb_put 1 1 'A'
    fb_put 2 3 'B'
    fb_emit
    check '输出两格' "${ESC}[1;1HA${ESC}[2;3HB" "$FRAME_BUF"
    check '输出后脏表清空' 0 "${#FB_DIRTY[@]}"

    # 没有新写入时再 emit 不应产生任何输出
    fb_emit
    check '再 emit 不输出' "${ESC}[1;1HA${ESC}[2;3HB" "$FRAME_BUF"

    # emit 是追加，不清空已有内容
    FRAME_BUF='PRE'
    fb_put 1 2 'C'
    fb_emit
    check 'emit 追加到 FRAME_BUF' "PRE${ESC}[1;2HC" "$FRAME_BUF"
}

test_case3 ()
{
    printf '\n== 擦除 ==\n'

    fb_init 10 5
    FRAME_BUF=''
    fb_put 4 4 'Z'
    fb_emit
    fb_clear 4 4
    fb_emit
    check '清空后输出空格' "${ESC}[4;4HZ${ESC}[4;4H " "$FRAME_BUF"
    check '格子内容为空' '' "$(fb_get 4 4)"
}

test_case4 ()
{
    printf '\n== 边界 ==\n'

    fb_init 10 5
    FRAME_BUF=''
    fb_put 0 1 'X'
    fb_put 1 0 'X'
    fb_put 11 1 'X'
    fb_put 1 6 'X'      # 合法：(x=6 ≤ 宽 10)，不该被丢
    fb_put 6 1 'X'      # 越界：(y=6 > 高 5)
    check '只有合法写入弄脏（1 格）' 1 "${#FB_DIRTY[@]}"
    fb_emit
    check '越界写入被忽略、合法写入保留' "${ESC}[1;6HX" "$FRAME_BUF"
}

test_case5 ()
{
    printf '\n== 同一格写两次 ==\n'

    fb_init 10 5
    FRAME_BUF=''
    fb_put 2 2 'X'
    fb_put 2 2 'Y'
    fb_emit
    # 两次都输出也可以，但最后一次必须生效
    check '最终值以最后一次为准' 'Y' "$(fb_get 2 2)"
    check '输出末尾是 Y' 'Y' "${FRAME_BUF: -1}"
}

test_case6 ()
{
    printf '\n== 移动：清旧格 + 写新格 ==\n'

    fb_init 10 5
    FRAME_BUF=''
    fb_put 3 3 'P'
    fb_emit
    FRAME_BUF=''
    fb_clear 3 3
    fb_put 3 4 'P'
    fb_emit
    check '旧格擦除 + 新格绘制' "${ESC}[3;3H ${ESC}[3;4HP" "$FRAME_BUF"
    check '旧格已空' '' "$(fb_get 3 3)"
    check '新格有值' 'P' "$(fb_get 3 4)"
}

test_case7 ()
{
    printf '\n== 屏幕比对器 ==\n'

    fb_init 10 5

    # 基本定位 + 字符
    fgrid_parse "${ESC}[1;1HA${ESC}[2;2HB"
    check '解析 (1,1)' 'A' "$(fgrid_at 1 1)"
    check '解析 (2,2)' 'B' "$(fgrid_at 2 2)"
    check '其余为空格' ' ' "$(fgrid_at 3 3)"

    # SGR 颜色序列要跳过，不能把颜色当字符写进网格
    fgrid_parse "${ESC}[38;5;46m${ESC}[3;4HX${ESC}[0m"
    check '跳过 SGR，只写字符' 'X' "$(fgrid_at 3 4)"
    check 'SGR 不占格' ' ' "$(fgrid_at 3 5)"

    # 2J 清屏
    fgrid_parse "${ESC}[1;1HA${ESC}[2J"
    check '2J 之后全空' ' ' "$(fgrid_at 1 1)"

    # K 清到行尾
    fgrid_parse "${ESC}[1;1HAB${ESC}[1;2H${ESC}[K"
    check 'K 清掉本行剩余' ' ' "$(fgrid_at 1 2)"

    # 往返一致：fb_emit 的输出，解析回网格后必须等于 FB_CELL
    fb_init 10 5
    FRAME_BUF=''
    fb_put 1 1 "${C_RED:-}A"
    fb_put 2 5 'B'
    fb_put 5 10 'C'
    fb_emit
    fgrid_parse "$FRAME_BUF"
    check '往返一致（颜色+字符）' 0 "$(fgrid_diff_count)"

    # 擦除后再往返（增量应用，不清网格）
    FRAME_BUF=''
    fb_clear 2 5
    fb_emit
    fgrid_apply "$FRAME_BUF"
    check '擦除后往返一致' 0 "$(fgrid_diff_count)"

    printf '\n---- 共断言 %d 项，失败 %d 项 ----\n' "$CHECKS" "$FAILS"
    if (( FAILS == 0 )) ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
}

eval -- "$(AS_RUN_TEST_CASES)"

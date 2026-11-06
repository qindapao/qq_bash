#!/usr/bin/env bash

. ../../src/bashlib/grammar.sh
. ../libs/test_utils.sh

# =========================================================
# 【核心】Mock locale 命令，默认让 charmap 返回 UTF-8
# 这样可以精准测试函数内部各分支，不受宿主机影响
# =========================================================
locale ()
{
    case "$1" in
        charmap) echo "UTF-8" ;;
        *)       command locale "$@" ;;
    esac
}
export -f locale
# =========================================================

test_case1 ()
{
    # 场景：LC_ALL 被强设为 C，同时 LC_CTYPE 也被污染为 C。
    # charmap 被 Mock 为 UTF-8 → 通过。
    # probe 看到 LC_CTYPE=C → 返回 3 → 失败。
    # LC_ALL 非空 → 触发 LOCALE OVERRIDE 警告。
    (
        export LC_ALL=C
        export LC_CTYPE=C
        local get_info=
        get_info=$(grammar_set_locale 2>&1)
        if [[ "$get_info" == *"LOCALE OVERRIDE DETECTED: LC_ALL is set to 'C'"* ]] ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi
    )
}

test_case2 ()
{
    # 场景：没有 LC_ALL，但 LC_CTYPE 被污染成 C。
    # charmap 被 Mock 为 UTF-8 → 通过。
    # probe 失败。
    # LC_ALL 为空 → 走修复逻辑：export LC_COLLATE=C + 找到 UTF-8 locale 并 export LC_CTYPE。
    (
        unset LC_ALL LANG
        export LC_CTYPE=C
        grammar_set_locale 2>&1
        if [[ "$LC_CTYPE" == *"UTF"* && "$LC_COLLATE" == "C" ]] ; then
            log_test 1 2
        else
            log_test 0 2 ; return 1
        fi
    )
}

test_case3 ()
{
    # 场景：系统连 UTF-8 字符集都没有。
    # 局部重定义 locale，让 charmap 返回非 UTF-8（ANSI_X3.4-1968）。
    # probe 会失败（因为 LC_CTYPE 未设置或为 C）。
    # → 触发 "Strict UTF-8 required" 警告并 return 0。
    (
        locale ()
        {
            case "$1" in
                charmap) echo "ANSI_X3.4-1968" ;;
                *)       command locale "$@" ;;
            esac
        }
        export -f locale
        
        unset LC_ALL LANG LC_CTYPE LC_COLLATE
        
        local get_info=
        get_info=$(grammar_set_locale 2>&1)
        if [[ "$get_info" == *"Strict UTF-8 required"* ]] ; then
            log_test 1 3
        else
            log_test 0 3 ; return 1
        fi
    )
}

test_case4 ()
{
    (
        unset LC_ALL LANG
        # 用一个系统里一定存在的 locale 名
        # 如果 Bash 不认它，函数会自行修复，但不会报警告
        export LC_CTYPE="en_US.UTF-8"
        export LC_COLLATE="en_US.UTF-8"
        local get_info=
        grammar_set_locale 2>&1

        if [[ "$LC_COLLATE" == "C" ]] ; then
            log_test 1 4
        else
            log_test 0 4 ; return 1
        fi
    )
}

test_case5 ()
{
    # 场景：LC_ALL=""（空字符串），等同于未设置。
    # LC_CTYPE=C 让 probe 失败。
    # charmap Mock 为 UTF-8 → 通过。
    # 不应触发 LC_ALL 警告，应正常修复。
    (
        export LC_ALL=""
        unset LANG
        export LC_CTYPE=C
        grammar_set_locale 2>&1
        if [[ "$LC_CTYPE" == *"UTF"* && "$LC_COLLATE" == "C" ]] ; then
            log_test 1 5
        else
            log_test 0 5 ; return 1
        fi
    )
}

eval -- "$(AS_RUN_TEST_CASES)"

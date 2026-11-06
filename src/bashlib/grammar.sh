((_GRAMMAR_IMPORTED++)) && return 0

export -A BASH_GRAMMAR=()

#-------------------------------------------------------------------------------

die ()
{
    local tag=$1 ; shift
    printf "%s\n" "[$tag] $*" >&2
    printf "%s\n" "Call stack:" >&2
    local i
    for ((i=1; i<${#FUNCNAME[@]}; i++)); do
        echo "  $i: ${FUNCNAME[$i]}() at ${BASH_SOURCE[$i]}:${BASH_LINENO[$((i-1))]}" >&2
    done
}

#-------------------------------------------------------------------------------
# 确保 Bash 的 ${#str} / ${str:i:1} 按 UTF-8 字符而非字节处理。
#
# 【检查机制】
#   1. 物理探针：用 UTF-8 '中' 实测，若 ${#str}==1 则环境健康，
#       仅 export LC_COLLATE=C 后返回，不执行任何外部命令。
#       [注意]: LC_ALL 非空时，export LC_COLLATE=C 会被压制，
#           导致排序按语言规则而非 ASCII 字节序
#           ([a-z] 范围匹配不受影响)。
#   2. charmap 检查：若底层编码非 UTF-8，警告并退出。
#   3. LC_ALL 拦截：LC_ALL 优先级最高，库无权覆盖（避免污染 LC_TIME 等），
#       若已设置则发出警告，交由用户自行修复。
#   4. 自动修复：LC_ALL 未设置时，强制 LC_COLLATE=C，
#       并动态寻找可用 UTF-8 locale，export LC_CTYPE 完成修复。
grammar_set_locale ()
{
    local probe_zh ; printf -v probe_zh '\xe4\xb8\xad'
    if ((${#probe_zh}==1)) ; then
        # LC_ALL 有设置的情况下这个失效
        export LC_COLLATE=C
        return 0
    fi
    local charmap=$(locale charmap 2>/dev/null)
    if [[ "$charmap" != *[uU][tT][fF]-8* ]] &&
       [[ "$charmap" != *[uU][tT][fF]8* ]] ; then
        die WARN "Strict UTF-8 required. Now is: $charmap"
        return 0
    fi

    if [[ -n "$LC_ALL" ]] ; then
        local warn_str= cr=$'\n'
        warn_str+="$cr"
        warn_str+="================================================================$cr"
        warn_str+="LOCALE OVERRIDE DETECTED: LC_ALL is set to '${LC_ALL}'.$cr"
        warn_str+="Because LC_ALL has the highest priority in Bash and POSIX,$cr"
        warn_str+="this library CANNOT safely configure LC_CTYPE or LC_COLLATE$cr"
        warn_str+="without overwriting your global environment settings.$cr"
        warn_str+="--------------------------------------------------------------$cr"
        warn_str+="CONSEQUENCE:$cr"
        warn_str+="  If your application processes UTF-8 text (Chinese, Emoji, etc.),$cr"
        warn_str+="  string functions may fall back to BYTE-mode. Length and slicing$cr"
        warn_str+="  operations may corrupt multi-byte characters.$cr"
        warn_str+="  Also, sorting rules may not follow strict ASCII byte-order.$cr"
        warn_str+="--------------------------------------------------------------$cr"
        warn_str+="HOW TO FIX:$cr"
        warn_str+="  1. If you need UTF-8 support, please unset LC_ALL:$cr"
        warn_str+="         unset LC_ALL$cr"
        warn_str+="  2. If you only handle pure ASCII, you can ignore this warning.$cr"
        warn_str+="================================================================$cr"
        die WARN "$warn_str"
        return 0
    fi
    export LC_COLLATE=C

    # 收集系统可用的 UTF-8 locale
    local avail_locales_list old_ifs=$IFS
    avail_locales_list=$(locale -a 2>/dev/null |
                        grep -iE '^[^\.]+\.utf-?8(@[a-zA-Z0-9_-]+)?$')
    local -a avail_locales=()
    local IFS=$'\n' ; avail_locales=($avail_locales_list) ; IFS=$old_ifs

    # C:     无语言偏好的纯 UTF-8 环境
    # en_US: 美国 最通用的英文 UTF-8 Locale
    # zh_CN：中文（简体），中国大陆
    # zh_HK：中文（繁体），中国香港
    # zh_SG：中文（简体），新加坡
    # zh_TW：中文（繁体），中国台湾
    local chosen="" c=""

    for c in    "C.UTF-8" \
                "C.UTF8" \
                "en_US.UTF-8" \
                "en_US.UTF8" \
                "zh_CN.UTF-8" \
                "zh_CN.UTF8" \
                "zh_HK.UTF-8" \
                "zh_HK.UTF8" \
                "zh_TW.UTF-8" \
                "zh_TW.UTF8" \
                "zh_SG.UTF-8" \
                "zh_SG.UTF8" ; do
        if printf '%s\n' "${avail_locales[@]}" | grep -qix "$c"; then
            chosen="$c"
            break
        fi
    done
    if [[ -z "$chosen" && ${#avail_locales[@]} -gt 0 ]] ; then
        chosen="${avail_locales[0]}"
    fi

    if [[ -z "$chosen" ]] ; then
        die WARN '[grammar] Warning: no UTF-8 locale available; str funcs will operate on bytes.'
        return 0
    fi

    export LC_CTYPE="$chosen"
}

#-------------------------------------------------------------------------------

grammar_detect ()
{
    # *. 当前进程的命令替换
    local get_1
    if ( eval 'get_1=${ echo "1";}' 2>/dev/null ) ; then
        BASH_GRAMMAR[current_shell_process_replace]=1
    else
        BASH_GRAMMAR[current_shell_process_replace]=0
    fi

    # *. @K 变量替换
    local -A temp_assoc=(['1 2']='a b')
    # 必须在 子 shell 中去探测，不然脚本会因为语法错误而崩溃
    # 并且必须使用 eval 不然脚本会在第一次解析阶段就崩溃
    if ( eval 'test_at_k_expand=${temp_assoc[*]@K}' 2>/dev/null ) ; then
        BASH_GRAMMAR[at_k_var_substitution]=1
    else
        BASH_GRAMMAR[at_k_var_substitution]=0
    fi

    # 只有嵌入式无法使用，暂时不检查
    # # *. 检查进程替换是否可用 <(cmd)
    # if ( eval 'cat <(echo hi) >/dev/null' 2>/dev/null ); then
    #     BASH_GRAMMAR[process_substitution]=1
    # else
    #     BASH_GRAMMAR[process_substitution]=0
    # fi
    
    # *. 检查 patsub_replacement
    if shopt | grep -wq "^patsub_replacement" ; then
        BASH_GRAMMAR[patsub_replacement]=1
    else
        BASH_GRAMMAR[patsub_replacement]=0
    fi

    # 打桩验证低版本特性
    # BASH_GRAMMAR[current_shell_process_replace]=0
    # BASH_GRAMMAR[at_k_var_substitution]=0
    # BASH_GRAMMAR[patsub_replacement]=0

    local -a bash_grammar=()
    local key
    for key in "${!BASH_GRAMMAR[@]}" ; do
        bash_grammar+=("$key" "${BASH_GRAMMAR[$key]}")
    done

    printf '%s\n' 'BASH_GRAMMAR:'
    printf '    %s => %s\n' "${bash_grammar[@]}"
}

# 注意：模块加载阶段执行代码可能在存在环形依赖时导致初始化失败。
# 只有当执行的函数完全在本模块内部且不依赖其他模块时，才是安全的。
grammar_detect
grammar_set_locale
readonly BASH_GRAMMAR

#-------------------------------------------------------------------------------

# 兼容性宏 
_ret_s='declare o=$REPLY ; REPLY='
_ret_s_='o=$REPLY ; REPLY='
_ret_i='declare -i o=$REPLY ; REPLY='

_ret_a='declare -a "o=($REPLY)" ; REPLY='
_ret_A='declare -A "o=($REPLY)" ; REPLY='
_ret_e='set -- "$?" ; REPLY= ; return $1'

_ret_g_s='declare -g o=$REPLY ; REPLY='
_ret_g_i='declare -gi o=$REPLY ; REPLY='
_ret_g_a='declare -ga "o=($REPLY)" ; REPLY='
_ret_g_A='declare -gA "o=($REPLY)" ; REPLY='
#-------------------------------------------------------------------------------

return 0


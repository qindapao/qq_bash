((_GRAMMAR_IMPORTED++)) && return 0

export -A BASH_GRAMMAR=()

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
readonly BASH_GRAMMAR

return 0

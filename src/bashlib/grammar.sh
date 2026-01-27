((_GRAMMAR_IMPORTED++)) && return 0

export -A BASH_GRAMMAR=()

grammar_detect ()
{
    # 1. 当前进程的命令替换
    local get_1
    { get_1=${ echo "1";} ; } 2>/dev/null
    if [[ "$get_1" == '1' ]] ; then
        BASH_GRAMMAR[current_shell_process_replace]=1
    else
        BASH_GRAMMAR[current_shell_process_replace]=0
    fi

    # 2. printf的时间打印
    printf '%(%Y_%m_%d_%H_%M_%S)T' -1 &>/dev/null
    if (($?)) ; then
        BASH_GRAMMAR[printf_time]=0
    else
        BASH_GRAMMAR[printf_time]=1
    fi
}
grammar_detect
readonly BASH_GRAMMAR

return 0

((_BASE_CLASS_IMPORTED++)) && return 0

. "${BASH_SOURCE[0]%/*}/trie.sh"
. "${BASH_SOURCE[0]%/*}/meta.sh"

#-------------------------------------------------------------------------------

setup_base_class ()
{
    local tr_s=$1 tr_i=$2 tr_k=$3
    local tr_value1=$4
    local tr_value2=$5
    local tr_cnt_demo=$6

    trie_insert_token_dict  "$tr_s" "$tr_i" "$tr_k" \
                            "{CLASS}" "base_class" \
                            "{SELF}" "$tr_s $tr_i" \
                            "{P1}" "$tr_value1" \
                            "{P2}" "$tr_value2" \
                            "{CNT}" "$tr_cnt_demo" \
                            "{ELEMENTS}" "$TR_VALUE_NULL_ARR"
}

#-------------------------------------------------------------------------------

new_base_class ()
{
    local tr_s=$1 tr_i=$2 tr_k=$3
    local tr_value1=$4
    local tr_value2=$5
    local tr_cnt_demo=$6
    
    NS["$tr_s.$tr_i"]=$tr_k
    setup_base_class  "$tr_s" "$tr_i" "$tr_k" \
                    "$tr_value1" "$tr_value2" "$tr_cnt_demo" 

    # bless_base_class "$tr_s" "$tr_i" "$tr_k"

    return 0
}

#-------------------------------------------------------------------------------

bless_base_class () { bless base_class "$@" ; }

#-------------------------------------------------------------------------------

cut_plus_base_class ()
{
    local -n tr_n=$1
    local tr_s=$1
    local tr_i=$2
    local tr_k=${NS[$tr_s.$tr_i]}

    local tr_class=${tr_n[$tr_k{CLASS}$X]}
    ${FN[$tr_class.SUPER.${FUNCNAME[0]}]} $tr_s $tr_i
    
    local tr_cnt=${tr_n[$tr_k{CNT}$X]}
    ((tr_cnt++))
    ((tr_cnt++))
    ((tr_cnt++))
    tr_n[$tr_k{CNT}$X]=$tr_cnt

}

#-------------------------------------------------------------------------------

print_self_base_class ()
{
    local tr_s=$1 tr_i=$2
    local tr_k=${NS[$tr_s.$tr_i]}
    trie_dump "$tr_s" "$tr_k"
}

#-------------------------------------------------------------------------------

haha_base_class () { : ; }

#-------------------------------------------------------------------------------

special_base_base_class ()
{
    :
}

#-------------------------------------------------------------------------------

delete_last_element_base_class ()
{
    local tr_s=$1 tr_i=$2
    local tr_k=${NS[$tr_s.$tr_i]}

    local -a "tr_delete_info=(${|trie_delete "$tr_s" "$tr_k{ELEMENTS}$X[-1]$X";})"
    ((${#tr_delete_info[@]})) && {
        unset -v 'NS[$tr_s.$tr_i]'
    }
}

#-------------------------------------------------------------------------------

return 0


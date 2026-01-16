((_BASE_CLASS_IMPORTED++)) && return 0

. "${BASH_SOURCE[0]%/*}/trie.sh"
. "${BASH_SOURCE[0]%/*}/meta.sh"

#-------------------------------------------------------------------------------

setup_base_class ()
{
    local tr_na=$1
    local tr_ni=$2
    local tr_np=$3
    local tr_value1=$4
    local tr_value2=$5
    local tr_cnt_demo=$6

    trie_qinserts   "$tr_na" common "$tr_np" \
                    "{SELF}$X" "$tr_na" \
                    "{P1}$X" "$tr_value1" \
                    "{P2}$X" "$tr_value2" \
                    "{CNT}$X" "$tr_cnt_demo"

    # Place other objects
    trie_insert "$tr_na" "$tr_np{ELEMENTS}$X" "$TR_VALUE_NULL_ARR" "$tr_ni" "$tr_np"
}

#-------------------------------------------------------------------------------

new_base_class ()
{
    local tr_na=$1
    local tr_ni=$2
    local tr_np=$3
    local tr_value1=$4
    local tr_value2=$5
    local tr_cnt_demo=$6
    
    NS_MAP["$tr_na.$tr_ni"]=$tr_np
    setup_base_class  "$tr_na" "$tr_ni" "$tr_np" \
                    "$tr_value1" "$tr_value2" "$tr_cnt_demo" 

    bless_base_class "$tr_na" "$tr_ni" "$tr_np"

    return 0
}

#-------------------------------------------------------------------------------

bless_base_class () { bless base_class "$@" ; }

#-------------------------------------------------------------------------------

cut_plus_base_class ()
{
    local -n tr_ns=$1
    local tr_na=$1
    local tr_ni=$2
    local tr_k=${NS_MAP[$tr_na.$tr_ni]}

    ${tr_ns[$tr_k{SUPER}$X{${FUNCNAME[0]}}$X]}
    
    local tr_cnt=${|trie_get_leaf "$tr_na" "$tr_k{CNT}$X";}
    ((tr_cnt++))
    ((tr_cnt++))
    ((tr_cnt++))
    tr_ns[$tr_k{CNT}$X]=$tr_cnt
}

#-------------------------------------------------------------------------------

print_self_base_class ()
{
    local -n tr_ns=$1
    local tr_na=$1
    local tr_ni=$2
    local tr_k=${NS_MAP[$tr_na.$tr_ni]}
    trie_dump "$tr_na" "$tr_k"
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
    local -n tr_ns=$1
    local tr_na=$1
    local tr_ni=$2
    local tr_k=${NS_MAP[$tr_na.$tr_ni]}

    local -a "tr_delete_info=(${|trie_delete "$tr_na" "$tr_k{ELEMENTS}$X[-1]$X";})"
    ((${#tr_delete_info[@]})) && {
        unset -v 'NS_MAP[$tr_na.$tr_ni]'
    }
}

#-------------------------------------------------------------------------------

return 0


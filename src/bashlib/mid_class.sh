((_MID_CLASS_IMPORTED++)) && return 0

. "${BASH_SOURCE[0]%/*}/trie.sh"
. "${BASH_SOURCE[0]%/*}/meta.sh"
. "${BASH_SOURCE[0]%/*}/base_class.sh"

#-------------------------------------------------------------------------------

setup_mid_class ()
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

new_mid_class ()
{
    local tr_na=$1
    local tr_ni=$2
    local tr_np=$3
    local tr_value1=$4
    local tr_value2=$5
    local tr_cnt_demo=$6

    setup_mid_class  "$tr_na" "$tr_ni" "$tr_np" \
                    "$tr_value1" "$tr_value2" "$tr_cnt_demo" 

    bless_mid_class "tr_na" "$tr_ni" "$tr_np"
}

#-------------------------------------------------------------------------------

bless_mid_class ()
{
    # Bless your parents first and then yourself
    bless_base_class "$@"
    bless mid_class "$@"
}

#-------------------------------------------------------------------------------

cut_plus_mid_class ()
{
    local -n tr_ns=$1
    local tr_na=$1
    local tr_ni=$2
    local tr_k=${NS_MAP[$tr_na.$tr_ni]}

    ${tr_ns[$tr_k{SUPER}$X{${FUNCNAME[0]}}$X]}
    
    local tr_cnt=${|trie_get_leaf "$tr_na" "$tr_k{CNT}$X";}
    ((tr_cnt++))
    ((tr_cnt++))
    tr_ns[$tr_k{CNT}$X]=$tr_cnt
}

#-------------------------------------------------------------------------------

haha_mid_class ()
{
    local -n tr_ns=$1
    local tr_na=$1
    local tr_ni=$2
    echo "$tr_na, Hello world!"
}

#-------------------------------------------------------------------------------

special_mid_mid_class ()
{
    :
}

#-------------------------------------------------------------------------------

return 0


((_MID_CLASS_IMPORTED++)) && return 0

. "${BASH_SOURCE[0]%/*}/trie.sh"
. "${BASH_SOURCE[0]%/*}/meta.sh"
. "${BASH_SOURCE[0]%/*}/base_class.sh"

#-------------------------------------------------------------------------------

setup_mid_class ()
{
    local tr_s=$1 tr_i=$2 tr_k=$3
    local tr_value1=$4
    local tr_value2=$5
    local tr_cnt_demo=$6

    trie_insert_token_dict "$tr_s" "$tr_k" "$tr_s" "$tr_i" "{SELF}"
    trie_insert_token_dict "$tr_s" "$tr_k" "$tr_value1" "$tr_i" "{P1}"
    trie_insert_token_dict "$tr_s" "$tr_k" "$tr_value2" "$tr_i" "{P2}"
    trie_insert_token_dict "$tr_s" "$tr_k" "$tr_cnt_demo" "$tr_i" "{CNT}"

    # Place other objects
    trie_insert_token_dict "$tr_s" "$tr_k" "$TR_VALUE_NULL_ARR" "$tr_i" "{ELEMENTS}"
}

#-------------------------------------------------------------------------------

new_mid_class ()
{
    local tr_s=$1 tr_i=$2 tr_k=$3
    local tr_value1=$4
    local tr_value2=$5
    local tr_cnt_demo=$6

    setup_mid_class  "$tr_s" "$tr_i" "$tr_k" \
                    "$tr_value1" "$tr_value2" "$tr_cnt_demo" 

    bless_mid_class "tr_s" "$tr_i" "$tr_k"
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
    local -n tr_n=$1
    local tr_s=$1 tr_i=$2
    local tr_k=${NS_MAP[$tr_s.$tr_i]}

    ${tr_n[$tr_k{SUPER}$X{${FUNCNAME[0]}}$X]}
    
    local tr_cnt=${|trie_get_leaf "$tr_s" "$tr_k{CNT}$X";}
    ((tr_cnt++))
    ((tr_cnt++))
    tr_n[$tr_k{CNT}$X]=$tr_cnt
}

#-------------------------------------------------------------------------------

haha_mid_class ()
{
    local tr_s=$1 tr_i=$2 tr_k=$3
    echo "$tr_s, Hello world!"
}

#-------------------------------------------------------------------------------

special_mid_mid_class ()
{
    :
}

#-------------------------------------------------------------------------------

return 0


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

    trie_insert_token_dict  "$tr_s" "$tr_i" "$tr_k" \
                            "{CLASS}" "mid_class" \
                            "{SELF}" "$tr_s $tr_i" \
                            "{P1}" "$tr_value1" \
                            "{P2}" "$tr_value2" \
                            "{CNT}" "$tr_cnt_demo" \
                            "{ELEMENTS}" "$TR_VALUE_NULL_ARR"
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

    # bless_mid_class "tr_s" "$tr_i" "$tr_k"
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
    local tr_s=$1
    local tr_i=$2
    local tr_k=${NS[$tr_s.$tr_i]}

    local tr_class=${tr_n[$tr_k{CLASS}$X]}
    ${FN[$tr_class.SUPER.${FUNCNAME[0]}]} $tr_s $tr_i
    
    local tr_cnt=${tr_n[$tr_k{CNT}$X]}
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


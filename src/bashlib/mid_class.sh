((_MID_CLASS_IMPORTED++)) && return 0

. "${BASH_SOURCE[0]%/*}/trie.sh"
. "${BASH_SOURCE[0]%/*}/meta.sh"
. "${BASH_SOURCE[0]%/*}/base_class.sh"

#-------------------------------------------------------------------------------

setup_mid_class ()
{
    local tr_self=$1
    local tr_my_obj_name=$2
    local tr_value1=$3
    local tr_value2=$4
    local tr_cnt_demo=$5

    trie_insert "$tr_self" "{SELF}$X" "$tr_my_obj_name"
    trie_insert "$tr_self" "{P1}$X" "$tr_value1"
    trie_insert "$tr_self" "{P2}$X" "$tr_value2"
    trie_insert "$tr_self" "{CNT}$X" "$tr_cnt_demo"
}

#-------------------------------------------------------------------------------

new_mid_class ()
{
    local tr_my_obj_name=$1
    local tr_value1=$2
    local tr_value2=$3
    local tr_cnt_demo=$4

    local -A "tr_my_obj=(${|trie_init "${TR_TYPE_OBJ}";})"
    
    setup_mid_class "tr_my_obj" "$tr_my_obj_name" "$tr_value1" "$tr_value2" "$tr_cnt_demo"
    bless_mid_class "tr_my_obj" "$tr_my_obj_name"

    REPLY=${tr_my_obj[*]@K}
    return 0
}

#-------------------------------------------------------------------------------

bless_mid_class ()
{
    # Bless your parents first and then yourself
    bless_base_class "$1" "$2"
    bless mid_class "$1" "$2"
}

#-------------------------------------------------------------------------------

cut_plus_mid_class ()
{
    local -n tr_self=$1

    ${tr_self[{SUPER}$X{${FUNCNAME[0]}}$X]}

    local tr_cnt=${|trie_get_leaf "$1" "{CNT}$X";}
    ((tr_cnt++))
    tr_self[{CNT}$X]=$tr_cnt
}

#-------------------------------------------------------------------------------

haha_mid_class ()
{
    local tr_self=$1
    echo "$tr_self, Hello world!"
}

#-------------------------------------------------------------------------------

special_mid_mid_class ()
{
    :
}

#-------------------------------------------------------------------------------

return 0


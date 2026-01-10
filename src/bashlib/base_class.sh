((_BASE_CLASS_IMPORTED++)) && return 0

. "${BASH_SOURCE[0]%/*}/trie.sh"
. "${BASH_SOURCE[0]%/*}/meta.sh"

setup_base_class ()
{
    local tr_self=$1
    local tr_my_obj_name=$2
    local tr_value1=$3
    local tr_value2=$4
    local tr_cnt_demo=$5

    trie_insert "$tr_self" "{SELF}$S" "$tr_my_obj_name"
    trie_insert "$tr_self" "{P1}$S" "$tr_value1"
    trie_insert "$tr_self" "{P2}$S" "$tr_value2"
    trie_insert "$tr_self" "{CNT}$S" "$tr_cnt_demo"
}

new_base_class ()
{
    local tr_my_obj_name=$1
    local tr_value1=$2
    local tr_value2=$3
    local tr_cnt_demo=$4

    local -A "tr_my_obj=(${|trie_init "${TR_TYPE_OBJ}";})"
    
    setup_base_class "tr_my_obj" "$tr_my_obj_name" "$tr_value1" "$tr_value2" "$tr_cnt_demo" 
    bless_base_class "tr_my_obj" "$tr_my_obj_name"

    REPLY=${tr_my_obj[*]@K}
    return 0
}

bless_base_class ()
{
    bless base_class "$1" "$2"
}

cut_plus_base_class ()
{
    local -n tr_self=$1
    local tr_cnt=${|trie_get_leaf "$1" "{CNT}$S";}
    ((tr_cnt++))
    ((tr_cnt++))
    tr_self[{CNT}$S]=$tr_cnt
}

print_self_base_class ()
{
    local tr_self=$1
    trie_dump "$tr_self"
}

haha_base_class () { : ; }

return 0


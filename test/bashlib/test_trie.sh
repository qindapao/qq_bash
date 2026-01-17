#!/usr/bin/env bash

. ../../src/bashlib/trie.sh
. ../libs/test_utils.sh

# trie_insert
test_case1 ()
{
    # 初始化为对象节点
    test_case1_inner1 ()
    {
        local -A "t1=(${|trie_init "$TR_TYPE_OBJ";})"
        local -A t1_init_spec=(
            [1.type]=1
            [max_index]=2
            )
        if assert_array 'A' t1 t1_init_spec ; then
            log_test 1 1
        else
            log_test 0 1 ;return 1
        fi

        trie_insert t1 "{key1}$X" "value1"
        local -A t1_insert_spec=(
            [1.type]=1
            [1.children]="'{key1}'"
            ["1.child.{key1}"]=2
            ["{key1}$X"]=value1
            [2.key]="{key1}$X"
            [max_index]=3
            )

        # printf "%s=>%s\n" "${t1[@]@k}"

        if assert_array 'A' t1 t1_insert_spec ; then
            log_test 1 2
        else
            log_test 0 2 ;return 1
        fi
    }

    
    # 对象的嵌套插入
    test_case1_inner2 ()
    {
        local -A "t1=(${|trie_init "$TR_TYPE_OBJ";})"
        trie_inserts t1 "{key1}$X[2]$X[2]$X" "key1_2_2"                \
                        "{key1}$X[1]$X[1]$X" "null0_change"            \
                        "{key1}$X[3]$X[2]$X" "new_value"               \
                        "{key1}$X[3]$X[0]$X" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$X[3]$X[0]$X{x3}$X" "1.11"              \
                        "{key1}$X[3]$X[1]$X" "$TR_VALUE_NULL_ARR"      \
                        "{key1}$X[3]$X[1]$X[5]$X" "$TR_VALUE_NULL_OBJ" \
                        "{key1}$X[3]$X[1]$X[5]$X{key11}$X" "xx1"       \
                        "{key1}$X[3]$X[1]$X[5]$X{key1}$X" "xx2"        \
                        "{key1}$X[3]$X[1]$X[5]$X{c}$X" "c"             \
                        "{key1}$X[3]$X[1]$X[5]$X{b}$X" "c"             \
                        "{key1}$X[3]$X[1]$X[5]$X{a}$X" "c"             \
                        "{key1}$X[3]$X[1]$X[5]$X{m}$X" "c"             \
                        "{key1}$X[3]$X[1]$X[5]$X{key2}$X" "c"          \
                        "{key1}$X[3]$X[1]$X[5]$X{key3}$X" "c"          \
                        "{key1}$X[3]$X[3]$X" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$X[3]$X[4]$X" "$TR_VALUE_NULL_ARR"      \
                        "{key1}$X[3]$X[5]$X" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$X[3]$X[6]$X" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$X[3]$X[7]$X" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$X[3]$X[-4]$X" "$TR_VALUE_NULL_ARR"     \
                        "{key2}${ohter_lev1}$X" "$TR_VALUE_NULL_OBJ"

        local str1="${ trie_dump t1 "" 4 $((2#011));}"
        trie_delete t1 "{key1}$X[2]$X"
        local str2="${ trie_dump t1 "" 4 $((2#011));}"
        diff_two_str_side_by_side "$str1" "$str2" "t1" "t1_delete"
        
        local -A "t2=(${|trie_init "$TR_TYPE_OBJ";})"
        trie_inserts t2 "{key1}$X[1]$X[1]$X" "null0_change"            \
                        "{key1}$X[2]$X[2]$X" "new_value"               \
                        "{key1}$X[2]$X[0]$X" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$X[2]$X[0]$X{x3}$X" "1.11"              \
                        "{key1}$X[2]$X[1]$X" "$TR_VALUE_NULL_ARR"      \
                        "{key1}$X[2]$X[1]$X[5]$X" "$TR_VALUE_NULL_OBJ" \
                        "{key1}$X[2]$X[1]$X[5]$X{key11}$X" "xx1"       \
                        "{key1}$X[2]$X[1]$X[5]$X{key1}$X" "xx2"        \
                        "{key1}$X[2]$X[1]$X[5]$X{c}$X" "c"             \
                        "{key1}$X[2]$X[1]$X[5]$X{b}$X" "c"             \
                        "{key1}$X[2]$X[1]$X[5]$X{a}$X" "c"             \
                        "{key1}$X[2]$X[1]$X[5]$X{m}$X" "c"             \
                        "{key1}$X[2]$X[1]$X[5]$X{key2}$X" "c"          \
                        "{key1}$X[2]$X[1]$X[5]$X{key3}$X" "c"          \
                        "{key1}$X[2]$X[3]$X" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$X[2]$X[4]$X" "$TR_VALUE_NULL_ARR"      \
                        "{key1}$X[2]$X[5]$X" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$X[2]$X[6]$X" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$X[2]$X[7]$X" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$X[2]$X[-4]$X" "$TR_VALUE_NULL_ARR"     \
                        "{key2}${ohter_lev1}$X" "$TR_VALUE_NULL_OBJ"

        # trie_dump t2 "" 4 $((2#111));
        if trie_equals t1 t2 ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi

        return 0
    }

    test_case1_inner3 ()
    {
        local -A "t1=(${|trie_init "$TR_TYPE_OBJ";})"

        trie_inserts t1 "{a}$X{b}$X{c}$X" "1" \
                        "{a}$X{b}$X{c1}$X" "2" \
                        "{a}$X{b}$X{c2}$X" "$TR_VALUE_NULL_OBJ" \
                        "{a}$X{b}$X{c3}$X" "$TR_VALUE_NULL_ARR" \
                        "{a}$X{c}$X[4]$X" "$TR_VALUE_NULL"

        local -A "t2=(${|trie_init "$TR_TYPE_ARR";})"

        trie_inserts t2 "[0]$X(4)$X{c}$X" "t2_1" \
                        "[0]$X(2)$X{c1}$X" "t2_2"

        local -a "my_graft_info=(${|trie_graft t1 "{a}$X{c}$X[4]$X" t2;})"

        if [[ "${my_graft_info[0]}" == '13' ]] ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi

        local abc ; abc=${|trie_get_leaf t1 "{a}$X{c}$X[4]$X[0]$X[2]$X{c1}$X";}
        trie_insert t1 "{a}$X{c}$X[4]$X[0]$X[2]$X{c1}$X" "18.2"
        local abc ; abc=${|trie_get_leaf t1 "{a}$X{c}$X[4]$X[0]$X[2]$X{c1}$X";}
        trie_insert t1 "{a}$X{c}$X[4]$X[0]$X[0]$X" "18.2"
        trie_insert t1 "{a}$X{c}$X[5]$X" "$TR_VALUE_NULL_ARR"
        trie_insert t1 "{a}$X{c}$X[5]$X[0]$X" "xx_1"

        trie_delete t1 "{a}$X{b}$X"

        local -A "t1_rebuild=(${|trie_id_rebuild t1;})"


        trie_insert t1 "{a}$X{m}$X" "$TR_VALUE_NULL_OBJ"
        trie_insert t1_rebuild "{a}$X{m}$X" "$TR_VALUE_NULL_OBJ"
        
        if trie_equals t1 t1_rebuild ; then
            log_test 1 2
        else
            log_test 0 2 ; return 1
        fi
        
        return 0
    }

    test_case1_inner4 ()
    {
        local -A "t1=(${|trie_init "$TR_TYPE_OBJ";})"

        trie_inserts t1 "{a 1}$X{b}$X{c}$X" "1" \
                        "{a 1}$X{b}$X{c1}$X" "2" \
                        "{a 1}$X{b}$X{c2}$X" "$TR_VALUE_NULL_OBJ" \
                        "{a 1}$X{b}$X{c3}$X" "$TR_VALUE_NULL_ARR" \
                        "{a 1}$X{c}$X[4]$X" "xx"
        trie_dump t1
        local tuple
        local old_ifs=$IFS ; local IFS=$'\n'
        local -a get_info=()
        for tuple in ${|trie_iter t1 "{a 1}$X{c}$X" $((2#11111));} ; do
            IFS=$old_ifs ; eval -- set -- $tuple
            get_info+=("$@")
        done
        declare -a get_info_spec=(
            [0]="<9>" [1]="6" [2]="0" [3]="$TR_VALUE_NULL" [4]="9"
            [5]="<10>" [6]="6" [7]="1" [8]="$TR_VALUE_NULL" [9]="10"
            [10]="<11>" [11]="6" [12]="2" [13]="$TR_VALUE_NULL" [14]="11" 
            [15]="<12>" [16]="6" [17]="3" [18]="$TR_VALUE_NULL" [19]="12"
            [20]="<13>" [21]="5" [22]="4" [23]="xx" [24]="13")
        if assert_array a get_info_spec get_info ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi

        return 0
    }


    test_case1_inner1 || return $?
    test_case1_inner2 || return $?
    test_case1_inner3 || return $?
    test_case1_inner4 || return $?
}

test_case2 ()
{
    local -A "t1=(${|trie_init "$TR_TYPE_OBJ";})"
    local -A "t2=(${|trie_init "$TR_TYPE_OBJ";})"
    
    trie_inserts t1 "{a}$X{b}$X{c}$X" "1" \
                    "{a}$X{m}$X" "$TR_VALUE_NULL"

    trie_inserts t2 "{a1}$X{b}$X{c}$X" "1" \
                    "{b}$X{m}$X[5]$X" "$TR_VALUE_NULL"

    trie_graft t1 "{x}$X" t2

    local -A "t1_spec=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_inserts t1_spec    "{a}$X{b}$X{c}$X" "1" \
                            "{a}$X{m}$X" "$TR_VALUE_NULL" \
                            "{x}$X{a1}$X{b}$X{c}$X" "1" \
                            "{x}$X{b}$X{m}$X[5]$X" "$TR_VALUE_NULL"

    if trie_equals t1 t1_spec ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
    
    return 0
}

test_case3 ()
{
    local -A "t1=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_inserts t1     "{a}$X{b}$X{c}$X" "1" \
                        "{a}$X{m}$X" "$TR_VALUE_NULL" \
                        "{x}$X{a1}$X{b}$X{c}$X" "1" \
                        "{x}$X{b}$X{m}$X[5]$X" "$TR_VALUE_NULL"

    trie_dump t1
    trie_push_leaf t1 "{a}$X{beee}$X" 'x'
    trie_push_leaf t1 "{a}$X{beee}$X" 'y'
    trie_push_leaf t1 "{a}$X{beee}$X" "$TR_VALUE_NULL_ARR"
    trie_push_leaf t1 "{a}$X{beee}$X" "$TR_VALUE_NULL"
    trie_push_leaf t1 "{a}$X{beee}$X" "$TR_VALUE_NULL_OBJ"

    trie_insert t1 "{a}$X{m}$X" "$TR_VALUE_NULL_ARR"
    trie_push_leaf t1 "{a}$X{m}$X" "x"

    local -A "t1_spec=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_inserts t1_spec "{a}$X{b}$X{c}$X" 1 \
                        "{a}$X{beee}$X[0]$X" x \
                        "{a}$X{beee}$X[1]$X" y \
                        "{a}$X{beee}$X[2]$X" "$TR_VALUE_NULL_ARR" \
                        "{a}$X{beee}$X[3]$X" "$TR_VALUE_NULL" \
                        "{a}$X{beee}$X[4]$X" "$TR_VALUE_NULL_OBJ" \
                        "{a}$X{m}$X[0]$X" x \
                        "{x}$X{a1}$X{b}$X{c}$X" 1 \
                        "{x}$X{b}$X{m}$X[9]$X" "$TR_VALUE_NULL" \
                        "{x}$X{b}$X{m}$X[0]$X" "4" \
                        "{x}$X{b}$X{m}$X[1]$X" "3" \
                        "{x}$X{b}$X{m}$X[2]$X" "2" \
                        "{x}$X{b}$X{m}$X[3]$X" "1"

    trie_unshift_leaf t1 "{x}$X{b}$X{m}$X" "1"
    trie_unshift_leaf t1 "{x}$X{b}$X{m}$X" "2"
    trie_unshift_leaf t1 "{x}$X{b}$X{m}$X" "3"
    trie_unshift_leaf t1 "{x}$X{b}$X{m}$X" "4"

    if trie_equals t1 t1_spec ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

test_case4 ()
{
    local -A "t1=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_inserts t1     "{a}$X{b}$X{c}$X" "1" \
                        "{a}$X{m}$X" "$TR_VALUE_NULL" \
                        "{x}$X{a1}$X{b}$X{c}$X" "1" \
                        "{x}$X{b}$X{m}$X[5]$X" "$TR_VALUE_NULL"

    local -A "t2=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_inserts t2     "{a}$X{b}$X{c}$X" "1" \
                        "{a}$X{m}$X" "$TR_VALUE_NULL" \
                        "{mxx}$X{a1}$X{b}$X{c}$X" "1" \
                        "{x}$X{b}$X{m}$X[5]$X" "$TR_VALUE_NULL"

    trie_push_tree t1 "{a}$X{x}$X{b}$X{m}$X" t2
    
    local -A "t1_spec=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_inserts t1_spec "{a}$X{b}$X{c}$X" "1" \
                        "{a}$X{m}$X" "$TR_VALUE_NULL" \
                        "{x}$X{a1}$X{b}$X{c}$X" "1" \
                        "{x}$X{b}$X{m}$X[5]$X" "$TR_VALUE_NULL" \
                        "{a}$X{x}$X{b}$X{m}$X[1]$X{a}$X{b}$X{c}$X" "1" \
                        "{a}$X{x}$X{b}$X{m}$X[1]$X{a}$X{m}$X" "$TR_VALUE_NULL" \
                        "{a}$X{x}$X{b}$X{m}$X[1]$X{mxx}$X{a1}$X{b}$X{c}$X" "1" \
                        "{a}$X{x}$X{b}$X{m}$X[1]$X{x}$X{b}$X{m}$X[5]$X" "$TR_VALUE_NULL" \
                        "{a}$X{x}$X{b}$X{m}$X[0]$X{new}$X" "new_value"


    local -A "t3=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_insert t3 "{new}$X" "new_value"
    trie_unshift_tree t1 "{a}$X{x}$X{b}$X{m}$X" t3

    if trie_equals t1 t1_spec ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    # trie_walk t1
}

test_case5 ()
{
    local -A "t1=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_inserts t1     "{a}$X" "1"                    \
                        "{b}$X" "101.3$X"              \
                        "{c}$X" "101.3"                \
                        "{d}$X" "${TR_VALUE_TRUE}"     \
                        "{e}$X" "${TR_VALUE_FALSE}"    \
                        "{f}$X" "${TR_VALUE_NULL_ARR}" \
                        "{g}$X" "${TR_VALUE_NULL_OBJ}" \
                        "{h}$X" "${TR_VALUE_NULL}"     \
                        "{i}$X" "null"                 \
                        "{j}$X" $'xxx\n  \n yyy'
    local flat_1 flat_1_ret
    local -A flat_1_spec=(
        [a]=1
        [b]="101.3$X"
        [c]="101.3"
        [d]="${TR_VALUE_TRUE}"
        [e]="${TR_VALUE_FALSE}"
        [f]="${TR_VALUE_NULL_ARR}"
        [g]="${TR_VALUE_NULL_OBJ}"
        [h]="${TR_VALUE_NULL}"
        [i]="null"
        [j]=$'xxx\n  \n yyy'
        )
    if flat_1=${|trie_to_flat_assoc t1;} ; then
        local -A "flat_1=($flat_1)"
    fi

    # cat -A <(trie_dump t1)

    if  [[ "${flat_1@a}" == *A* ]] &&
        assert_array A flat_1 flat_1_spec ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

test_case6 ()
{
    local -A "t1=(${|trie_init "$TR_TYPE_ARR";})"
    trie_inserts t1     "[10]$X" "1"                    \
                        "[14]$X" "101.3$X"              \
                        "[16]$X" "101.3"                \
                        "[17]$X" "${TR_VALUE_TRUE}"     \
                        "[18]$X" "${TR_VALUE_FALSE}"    \
                        "[19]$X" "${TR_VALUE_NULL_ARR}" \
                        "[20]$X" "${TR_VALUE_NULL_OBJ}" \
                        "[21]$X" "${TR_VALUE_NULL}"     \
                        "[22]$X" "null"                 \
                        "[23]$X" "xxx"
    local flat_1 flat_1_ret
    local -a flat_1_spec=(
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "1"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "101.3$X"
        "${TR_VALUE_NULL}"
        "101.3"
        "${TR_VALUE_TRUE}"
        "${TR_VALUE_FALSE}"
        "${TR_VALUE_NULL_ARR}"
        "${TR_VALUE_NULL_OBJ}"
        "${TR_VALUE_NULL}"
        "null"
        "xxx"
        )

    if flat_1=${|trie_to_flat_array t1;} ; then
        local -a "flat_1=($flat_1)"
    fi

    # cat -A <(trie_dump t1)

    if  [[ "${flat_1@a}" == *a* ]] &&
        assert_array a flat_1 flat_1_spec ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

test_case7 ()
{
    local -A "t1=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_inserts t1     "{x}$X{a}$X" "1"                    \
                        "{x}$X{b}$X" "101.3$X"              \
                        "{x}$X{c}$X" "101.3"                \
                        "{x}$X{d}$X" "${TR_VALUE_TRUE}"     \
                        "{y}$X{e}$X" "${TR_VALUE_FALSE}"    \
                        "{y}$X{f}$X" "${TR_VALUE_NULL_ARR}" \
                        "{y}$X{g}$X" "${TR_VALUE_NULL_OBJ}" \
                        "{y}$X{h}$X" "${TR_VALUE_NULL}"     \
                        "{y}$X{i}$X" "null"                 \
                        "{y}$X{j}$X" "xxx"
    local flat_1 flat_1_ret
    local -A flat_1_spec=(
        [a]=1
        [b]="101.3$X"
        [c]="101.3"
        [d]="${TR_VALUE_TRUE}"
        )
    if flat_1=${|trie_to_flat_assoc t1 "{x}$X";} ; then
        local -A "flat_1=($flat_1)"
    fi

    # cat -A <(trie_dump t1)
    # printf "%s => %s\n" "${flat_1[@]@k}"

    if  [[ "${flat_1@a}" == *A* ]] &&
        assert_array A flat_1 flat_1_spec ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

test_case8 ()
{
    local -A "t1=(${|trie_init "$TR_TYPE_ARR";})"
    local -A "t2=(${|trie_init "$TR_TYPE_ARR";})"

    local xxk=${|trie_inserts t2     "[0]$X[10]$X" "1"   \
                    "[0]$X[14]$X" "101.3$X"              \
                    "[1]$X[16]$X" "101.3"                \
                    "[1]$X[17]$X" "${TR_VALUE_TRUE}"     \
                    "[1]$X[18]$X" "${TR_VALUE_FALSE}"    \
                    "[1]$X[19]$X" "${TR_VALUE_NULL_ARR}" \
                    "[1]$X[20]$X" "${TR_VALUE_NULL_OBJ}" \
                    "[1]$X[21]$X" "${TR_VALUE_NULL}"     \
                    "[1]$X[22]$X" "null"                 \
                    "[1]$X[23]$X" "xxx";}

    local xxy=${|trie_qinserts t1 leaves "[0]$X" \
                "[10]$X" "1"                     \
                "[14]$X" "101.3$X" ;}

    local -a "xxy=($xxy)" 
    local -a "xxk=($xxk)"
    
    declare -a xxy_spec=(
        [0]="13" [1]="<2>$X<13>$X"
        [2]="17" [3]="<2>$X<17>$X")

    declare -a xxk_spec=(
        [0]="13" [1]="<2>$X<13>$X"
        [2]="17" [3]="<2>$X<17>$X"
        [4]="35" [5]="<18>$X<35>$X"
        [6]="36" [7]="<18>$X<36>$X"
        [8]="37" [9]="<18>$X<37>$X"
        [10]="38" [11]="<18>$X<38>$X"
        [12]="39" [13]="<18>$X<39>$X"
        [14]="40" [15]="<18>$X<40>$X"
        [16]="41" [17]="<18>$X<41>$X"
        [18]="42" [19]="<18>$X<42>$X")

    if  assert_array a xxy xxy_spec &&
        assert_array a xxk xxk_spec ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    local xxy=${|trie_qinserts t1 leaves "[1]$X" \
                "[16]$X" "101.3"                 \
                "[17]$X" "${TR_VALUE_TRUE}"      \
                "[18]$X" "${TR_VALUE_FALSE}"     \
                "[19]$X" "${TR_VALUE_NULL_ARR}"  \
                "[20]$X" "${TR_VALUE_NULL_OBJ}"  \
                "[21]$X" "${TR_VALUE_NULL}"      \
                "[22]$X" "null"                  \
                "[23]$X" "xxx" ;}

    local -a "xxy=($xxy)"

    local -a xxy_spec=(
        [0]="35" [1]="<18>$X<35>$X"
        [2]="36" [3]="<18>$X<36>$X"
        [4]="37" [5]="<18>$X<37>$X"
        [6]="38" [7]="<18>$X<38>$X"
        [8]="39" [9]="<18>$X<39>$X"
        [10]="40" [11]="<18>$X<40>$X"
        [12]="41" [13]="<18>$X<41>$X"
        [14]="42" [15]="<18>$X<42>$X")

    if assert_array a xxy xxy_spec ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

    if trie_equals t1 t2 ; then
        log_test 1 3
    else
        log_test 0 3 ; return 1
    fi

    local flat_1 flat_1_ret
    local -a flat_1_spec=(
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "1"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "${TR_VALUE_NULL}"
        "101.3$X"
        )

    if flat_1=${|trie_to_flat_array t1 '' 2;} ; then
        local -a "flat_1=($flat_1)"
    fi

    # cat -A <(trie_dump t1)
    # printf "%s\n" "${flat_1[@]}"

    if  [[ "${flat_1@a}" == *a* ]] &&
        assert_array a flat_1 flat_1_spec ; then
        log_test 1 4
    else
        log_test 0 4 ; return 1
    fi

    return 0
}

test_case9 ()
{
    local -A "t1=(${|trie_init "$TR_TYPE_ARR";})"
    trie_insert t1 "[0]$X{b}$X" "xx"
    trie_insert t1 "[1]$X{c}$X" "yy"

    local -a my_arr=("a 1" "b 2" "$TR_VALUE_NULL" "$TR_VALUE_NULL_OBJ" "$TR_VALUE_NULL_ARR")
    my_arr[10]=5
    local -a "node_info=(${|trie_flat_to_tree t1 "[0]$X{b}$X" my_arr;})"

    local -A "t2=(${|trie_init "$TR_TYPE_ARR";})"
    trie_insert t2 "[0]$X{b}$X" "$TR_VALUE_NULL"
    trie_insert t2 "[1]$X{c}$X" "yy"
    trie_insert t2 "[0]$X{b}$X[0]$X" "a 1"
    trie_insert t2 "[0]$X{b}$X[1]$X" "b 2"
    trie_insert t2 "[0]$X{b}$X[2]$X" "$TR_VALUE_NULL"
    trie_insert t2 "[0]$X{b}$X[3]$X" "$TR_VALUE_NULL_OBJ"
    trie_insert t2 "[0]$X{b}$X[4]$X" "$TR_VALUE_NULL_ARR"
    trie_insert t2 "[0]$X{b}$X[10]$X" "5"

    if trie_equals t1 t2 &&
       [[ "${node_info[0]}" == "6" ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
    
    return 0
}

test_case10 ()
{
    local -A "t1=(${|trie_init "$TR_TYPE_ARR";})"
    trie_insert t1 "[0]$X{b}$X" "xx"
    trie_insert t1 "[1]$X{c}$X" "yy"

    local -A my_arr=(['key 1']='value 1' [key2]="$TR_VALUE_NULL_ARR")
    local node_info=${|trie_flat_to_tree t1 "(0)$X{b}$X" my_arr;}
    local -a "node_info=($node_info)"

    local -A "t2=(${|trie_init "$TR_TYPE_ARR";})"
    trie_insert t2 "[0]$X{b}$X{key 1}$X" "value 1"
    trie_insert t2 "[0]$X{b}$X{key2}$X" "$TR_VALUE_NULL_ARR"
    trie_insert t2 "(1)$X{c}$X" "yy"
    trie_insert t2 "(1)$X{b}$X" "xx"
    
    if [[ "${node_info[0]}" == 7 ]] &&
        trie_equals t1 t2 ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

# test trie_get_tree
test_case11 ()
{
    local -A "t1=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_inserts t1 "{a}$X{b}$X" "1" \
                    "{a}$X{c}$X" "2" \
                    "{a}$X{m}$X[0]$X[2]$X" "2" \
                    "{a}$X{k}$X{key2}$X[2]$X" "4" \
                    "{b}$X{x}$X" "3" \
                    "{b}$X{y}$X" "3"

    local -A "t2=(${|trie_get_tree t1 "{a}$X";})"

    local -A "t2_spec=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_inserts t2_spec    "{b}$X" "1" \
                            "{c}$X" "2" \
                            "{m}$X[0]$X[2]$X" "2" \
                            "{k}$X{key2}$X[2]$X" "4"

    if trie_equals t2 t2_spec ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

test_case12 ()
{

    local -A "t1=(${|trie_init "$TR_TYPE_OBJ";})"

    local sp=$'\ngeg geg\n ge\ng  ge  '
    trie_qinserts   t1 leaves '' \
                    "{a}$X" $'geg\ngee\n  gg\n ' \
                    "{$sp}$X" $'2333\n geg\ngge  '
    local old_ifs=$IFS IFS=$'\n' tuple
    local -a get_params=()
    for tuple in ${|trie_iter t1 '' $((2#11111));} ; do
        IFS=$old_ifs ; local -a "tuple=($tuple)"
        get_params+=("${tuple[@]}")
    done
    local -a param_spec=(
        [5]=$'{\ngeg geg\n ge\ng  ge  }'
        [6]="5"
        [7]=$'{\ngeg geg\n ge\ng  ge  }'
        [8]=$'2333\n geg\ngge  '
        [9]="3"
        [0]="{a}"
        [1]="5"
        [2]="{a}"
        [3]=$'geg\ngee\n  gg\n '
        [4]="2"
        )

    if assert_array a get_params param_spec ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
    
    return 0
}

test_case13 ()
{
    
    local -A "t1=(${|trie_init "$TR_TYPE_ARR";})"
    local -a null_arr=()
    local -A null_obj=()
    local -a arr1=("a 1" "b 2")
    local -A obj1=(["a 1"]="c 3" ["b 2"]="d 4")

    trie_push_flat t1 '' null_obj 

    trie_push_flat t1 '' null_obj 
    trie_unshift_flat t1 '' null_arr 
    trie_unshift_flat t1 '' null_arr 

    trie_push_flat t1 "[2]$X{key1}$X{key2}$X" arr1
    trie_unshift_flat t1 "[2]$X{key1}$X{key2}$X" obj1
    trie_unshift_flat t1 "[2]$X{key1}$X{key2}$X" obj1
    trie_unshift_flat t1 "[2]$X{key1}$X{key2}$X" obj1
    trie_unshift_flat t1 "[2]$X{key1}$X{key2}$X" obj1
    trie_unshift_flat t1 "[2]$X{key1}$X{key2}$X" obj1
    trie_unshift_flat t1 "[2]$X{key1}$X{key2}$X" obj1
    trie_push_flat t1 "[2]$X{key1}$X{key2}$X" arr1
    trie_push_flat t1 "[2]$X{key1}$X{key2}$X" arr1
    trie_push_flat t1 "[2]$X{key1}$X{key2}$X" arr1
    trie_push_flat t1 "[2]$X{key1}$X{key2}$X" arr1

    trie_qinserts t1 common "[2]$X{key2}$X{key3}$X" \
                "{key1}$X" "vgege" \
                "{key2}$X" "vgege" \
                "{key3}$X" "vgege" \
                "{key4}$X" "vgege" \
                "{key5}$X" "vgege" \
                "{key6}$X" "vgege"

    trie_delete t1 "[2]$X{key1}$X{key2}$X[3]$X"
    trie_delete t1 "[2]$X{key1}$X{key2}$X[4]$X"
    trie_delete t1 "[2]$X{key1}$X{key2}$X[5]$X"
    trie_delete t1 "[2]$X{key1}$X{key2}$X[6]$X"

    trie_delete t1 "[2]$X{key2}$X"

    local -A "t1_rebuild=(${|trie_id_rebuild t1;})"

    if trie_equals t1 t1_rebuild ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

# pop/shift
test_case14 ()
{
    local -A "t1=(${|trie_init "$TR_TYPE_ARR";})"

    trie_inserts t1 "[0]$X{b}$X" "value1" \
                    "[1]$X{c}$X" "value2" \
                    "[2]$X{x}$X" "value3" \
                    "[3]$X{y}$X" "value4" \
                    "[4]$X{z}$X" "value5" \
                    "[5]$X[3]$X" "value5"

    local -A "get_tree=(${|trie_shift_tree t1 '';})"


    local -A "get_tree_spec=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_insert get_tree_spec "{b}$X" 'value1'

    local -A "t1_spec=(${|trie_init "$TR_TYPE_ARR";})"
    trie_inserts t1_spec \
                "[0]$X{c}$X" "value2" \
                "[1]$X{x}$X" "value3" \
                "[2]$X{y}$X" "value4" \
                "[3]$X{z}$X" "value5" \
                "[4]$X[3]$X" "value5"

    if  trie_equals get_tree get_tree_spec &&
        trie_equals t1 t1_spec ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
    
    return 0
}

test_case15 ()
{
    local -A "t1=(${|trie_init "$TR_TYPE_ARR";})"

    trie_inserts t1 "[0]$X{b}$X" "value1" \
                    "[0]$X{aage}$X" "value2" \
                    "[1]$X{c}$X" "value2" \
                    "[1]$X{c1}$X" "value1" \
                    "[1]$X{c2}$X" "valuec" \
                    "[2]$X{x}$X" "value3" \
                    "[3]$X{y}$X" "value4" \
                    "[4]$X{z}$X" "value5" \
                    "[5]$X[3]$X" "value5"

    local -a "arr=(${|trie_pop_to_flat_array t1;})"
    local -A "obj=(${|trie_shift_to_flat_assoc t1;})"

    local -a arr_spec=([0]=$'null'$X [1]=$'null'$X [2]=$'null'$X [3]="value5")
    local -A obj_spec=([b]="value1" [aage]="value2" )    

    if  assert_array a arr arr_spec &&
        assert_array A obj obj_spec ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

test_case16 ()
{
    local -A "t1=(${|trie_init "$TR_TYPE_ARR";})"

    local special_str1=$'gge\ngege g\n \t gegge'
    local special_str2=$'\ngege geg\ngg  ee'

    trie_inserts t1 "[0]$X{b}$X" "value1" \
                    "[0]$X{aage}$X" "value2" \
                    "[1]$X{$special_str1}$X" "$special_str2" \
                    "[1]$X{c1}$X" "$TR_VALUE_NULL_OBJ" \
                    "[1]$X{c2}$X" "$TR_VALUE_NULL_ARR" \
                    "[1]$X{c3}$X" "$TR_VALUE_NULL" \
                    "[1]$X{c4}$X" "190.22$X" \
                    "[1]$X{c5*[]@!{}}$X" "190.23*[]@!{}" \
                    "[1]$X{c6}$X" "$TR_VALUE_TRUE" \
                    "[1]$X{c7}$X" "$TR_VALUE_FALSE" \
                    "[1]$X{c8}$X" "strwxx" \
                    "[1]$X{gge中国ge}$X[0]$X" "null" \
                    "[1]$X{gge中国ge}$X[1]$X" "$TR_VALUE_NULL" \
                    "[1]$X{gge中国ge}$X[2]$X" "$TR_VALUE_TRUE" \
                    "[1]$X{gge中国ge}$X[3]$X" "1010$X" \
                    "[1]$X{gge中国ge}$X[4]$X" "1010.22" \
                    "[1]$X{gge中国ge}$X[5]$X" "gegege" \
                    "[2]$X{x}$X" "value3" \
                    "[3]$X{y}$X" "value4" \
                    "[4]$X{z}$X" "value5" \
                    "[5]$X[3]$X" "value5"

    local -A "t2=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_inserts t2 "{b}$X" "value1" \
                    "{aage}$X" "value2"


    # echo "${t1[5.children]}"

    local t1_json
    t1_json=${|trie_to_json t1;}

    local t1_json_slow
    t1_json_slow=${|trie_to_json_slow t1;}
    t1_json_slow=${|trie_to_json_slow t1;}

    # cat -A <(printf "%s" "$t1_json_slow")
    # cat -A <(printf "%s" "$t1_json")

    local json_spec='[
    {
        "aage": "value2",
        "b": "value1"
    },
    {
        "c1": {},
        "c2": [],
        "c3": null,
        "c4": 190.22,
        "c5*[]@!{}": "190.23*[]@!{}",
        "c6": true,
        "c7": false,
        "c8": "strwxx",
        "gge\ngege g\n \t gegge": "\ngege geg\ngg  ee",
        "gge中国ge": [
            "null",
            null,
            true,
            1010,
            "1010.22",
            "gegege"
        ]
    },
    {
        "x": "value3"
    },
    {
        "y": "value4"
    },
    {
        "z": "value5"
    },
    [
        null,
        null,
        null,
        "value5"
    ]
]'
    
    # echo "t1_json"
    # printf "%s\n" "$t1_json"

    # echo "json_spec"
    # printf "%s\n" "$json_spec"

    if [[ "$t1_json" == "$json_spec" ]] && [[ "$t1_json" == "$t1_json_slow" ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    local -A "my_recover_tree1=(${|trie_from_json "$json_spec";})"
    local -A "my_recover_tree2=(${|trie_from_json "$json_spec" 0;})"

    # cat -A <(trie_dump my_recover_tree1)

    if  trie_equals my_recover_tree1 t1 &&
        trie_equals my_recover_tree2 t2 ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi


    
    return 0
}


# step_test 9
eval -- "${|AS_RUN_TEST_CASES;}"


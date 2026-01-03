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
            [1]=1
            [1.type]=1
            [max_index]=2
            )
        if assert_array 'A' t1 t1_init_spec ; then
            log_test 1 1
        else
            log_test 0 1 ;return 1
        fi

        trie_insert t1 "{key1}$S" "value1"
        local -A t1_insert_spec=(
            [1]=1
            [1.type]=1
            [1.children]="{key1}$S"
            ["1.child.{key1}"]=2
            [2]=1
            ["{key1}$S"]=value1
            [2.key]="{key1}$S"
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
        trie_inserts t1 "{key1}$S[2]$S[2]$S" "key1_2_2"                \
                        "{key1}$S[1]$S[1]$S" "null0_change"            \
                        "{key1}$S[3]$S[2]$S" "new_value"               \
                        "{key1}$S[3]$S[0]$S" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$S[3]$S[0]$S{x3}$S" "1.11"              \
                        "{key1}$S[3]$S[1]$S" "$TR_VALUE_NULL_ARR"      \
                        "{key1}$S[3]$S[1]$S[5]$S" "$TR_VALUE_NULL_OBJ" \
                        "{key1}$S[3]$S[1]$S[5]$S{key11}$S" "xx1"       \
                        "{key1}$S[3]$S[1]$S[5]$S{key1}$S" "xx2"        \
                        "{key1}$S[3]$S[1]$S[5]$S{c}$S" "c"             \
                        "{key1}$S[3]$S[1]$S[5]$S{b}$S" "c"             \
                        "{key1}$S[3]$S[1]$S[5]$S{a}$S" "c"             \
                        "{key1}$S[3]$S[1]$S[5]$S{m}$S" "c"             \
                        "{key1}$S[3]$S[1]$S[5]$S{key2}$S" "c"          \
                        "{key1}$S[3]$S[1]$S[5]$S{key3}$S" "c"          \
                        "{key1}$S[3]$S[3]$S" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$S[3]$S[4]$S" "$TR_VALUE_NULL_ARR"      \
                        "{key1}$S[3]$S[5]$S" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$S[3]$S[6]$S" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$S[3]$S[7]$S" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$S[3]$S[-4]$S" "$TR_VALUE_NULL_ARR"     \
                        "{key2}${ohter_lev1}$S" "$TR_VALUE_NULL_OBJ"

        local str1="${ trie_dump t1 "" 4 $((2#011));}"
        trie_delete t1 "{key1}$S[2]$S"
        local str2="${ trie_dump t1 "" 4 $((2#011));}"
        diff_two_str_side_by_side "$str1" "$str2" "t1" "t1_delete"
        
        local -A "t2=(${|trie_init "$TR_TYPE_OBJ";})"
        trie_inserts t2 "{key1}$S[1]$S[1]$S" "null0_change"            \
                        "{key1}$S[2]$S[2]$S" "new_value"               \
                        "{key1}$S[2]$S[0]$S" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$S[2]$S[0]$S{x3}$S" "1.11"              \
                        "{key1}$S[2]$S[1]$S" "$TR_VALUE_NULL_ARR"      \
                        "{key1}$S[2]$S[1]$S[5]$S" "$TR_VALUE_NULL_OBJ" \
                        "{key1}$S[2]$S[1]$S[5]$S{key11}$S" "xx1"       \
                        "{key1}$S[2]$S[1]$S[5]$S{key1}$S" "xx2"        \
                        "{key1}$S[2]$S[1]$S[5]$S{c}$S" "c"             \
                        "{key1}$S[2]$S[1]$S[5]$S{b}$S" "c"             \
                        "{key1}$S[2]$S[1]$S[5]$S{a}$S" "c"             \
                        "{key1}$S[2]$S[1]$S[5]$S{m}$S" "c"             \
                        "{key1}$S[2]$S[1]$S[5]$S{key2}$S" "c"          \
                        "{key1}$S[2]$S[1]$S[5]$S{key3}$S" "c"          \
                        "{key1}$S[2]$S[3]$S" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$S[2]$S[4]$S" "$TR_VALUE_NULL_ARR"      \
                        "{key1}$S[2]$S[5]$S" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$S[2]$S[6]$S" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$S[2]$S[7]$S" "$TR_VALUE_NULL_OBJ"      \
                        "{key1}$S[2]$S[-4]$S" "$TR_VALUE_NULL_ARR"     \
                        "{key2}${ohter_lev1}$S" "$TR_VALUE_NULL_OBJ"

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

        trie_inserts t1 "{a}$S{b}$S{c}$S" "1" \
                        "{a}$S{b}$S{c1}$S" "2" \
                        "{a}$S{b}$S{c2}$S" "$TR_VALUE_NULL_OBJ" \
                        "{a}$S{b}$S{c3}$S" "$TR_VALUE_NULL_ARR" \
                        "{a}$S{c}$S[4]$S" "$TR_VALUE_NULL"

        local -A "t2=(${|trie_init "$TR_TYPE_ARR";})"

        trie_inserts t2 "[0]$S(4)$S{c}$S" "t2_1" \
                        "[0]$S(2)$S{c1}$S" "t2_2"

        local my_graft_id=${|trie_graft t1 "{a}$S{c}$S[4]$S" t2;}

        if [[ "$my_graft_id" == '13' ]] ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi

        local abc ; abc=${|trie_get_leaf t1 "{a}$S{c}$S[4]$S[0]$S[2]$S{c1}$S";}
        trie_insert t1 "{a}$S{c}$S[4]$S[0]$S[2]$S{c1}$S" "18.2"
        local abc ; abc=${|trie_get_leaf t1 "{a}$S{c}$S[4]$S[0]$S[2]$S{c1}$S";}
        trie_insert t1 "{a}$S{c}$S[4]$S[0]$S[0]$S" "18.2"
        trie_insert t1 "{a}$S{c}$S[5]$S" "$TR_VALUE_NULL_ARR"
        trie_insert t1 "{a}$S{c}$S[5]$S[0]$S" "xx_1"

        trie_delete t1 "{a}$S{b}$S"

        local -A "t1_rebuild=(${|trie_id_rebuild t1;})"


        trie_insert t1 "{a}$S{m}$S" "$TR_VALUE_NULL_OBJ"
        trie_insert t1_rebuild "{a}$S{m}$S" "$TR_VALUE_NULL_OBJ"
        
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

        trie_inserts t1 "{a 1}$S{b}$S{c}$S" "1" \
                        "{a 1}$S{b}$S{c1}$S" "2" \
                        "{a 1}$S{b}$S{c2}$S" "$TR_VALUE_NULL_OBJ" \
                        "{a 1}$S{b}$S{c3}$S" "$TR_VALUE_NULL_ARR" \
                        "{a 1}$S{c}$S[4]$S" "xx"
        trie_dump t1
        local tuple
        local old_ifs=$IFS ; local IFS=$'\n'
        local -a get_info=()
        for tuple in ${|trie_iter t1 "{a 1}$S{c}$S" $((2#11111));} ; do
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
    
    trie_inserts t1 "{a}$S{b}$S{c}$S" "1" \
                    "{a}$S{m}$S" "$TR_VALUE_NULL"

    trie_inserts t2 "{a1}$S{b}$S{c}$S" "1" \
                    "{b}$S{m}$S[5]$S" "$TR_VALUE_NULL"

    trie_graft t1 "{x}$S" t2

    local -A "t1_spec=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_inserts t1_spec    "{a}$S{b}$S{c}$S" "1" \
                            "{a}$S{m}$S" "$TR_VALUE_NULL" \
                            "{x}$S{a1}$S{b}$S{c}$S" "1" \
                            "{x}$S{b}$S{m}$S[5]$S" "$TR_VALUE_NULL"

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
    trie_inserts t1     "{a}$S{b}$S{c}$S" "1" \
                        "{a}$S{m}$S" "$TR_VALUE_NULL" \
                        "{x}$S{a1}$S{b}$S{c}$S" "1" \
                        "{x}$S{b}$S{m}$S[5]$S" "$TR_VALUE_NULL"

    trie_dump t1
    trie_push_leaf t1 "{a}$S{beee}$S" 'x'
    trie_push_leaf t1 "{a}$S{beee}$S" 'y'
    trie_push_leaf t1 "{a}$S{beee}$S" "$TR_VALUE_NULL_ARR"
    trie_push_leaf t1 "{a}$S{beee}$S" "$TR_VALUE_NULL"
    trie_push_leaf t1 "{a}$S{beee}$S" "$TR_VALUE_NULL_OBJ"

    trie_insert t1 "{a}$S{m}$S" "$TR_VALUE_NULL_ARR"
    trie_push_leaf t1 "{a}$S{m}$S" "x"

    local -A "t1_spec=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_inserts t1_spec "{a}$S{b}$S{c}$S" 1 \
                        "{a}$S{beee}$S[0]$S" x \
                        "{a}$S{beee}$S[1]$S" y \
                        "{a}$S{beee}$S[2]$S" "$TR_VALUE_NULL_ARR" \
                        "{a}$S{beee}$S[3]$S" "$TR_VALUE_NULL" \
                        "{a}$S{beee}$S[4]$S" "$TR_VALUE_NULL_OBJ" \
                        "{a}$S{m}$S[0]$S" x \
                        "{x}$S{a1}$S{b}$S{c}$S" 1 \
                        "{x}$S{b}$S{m}$S[9]$S" "$TR_VALUE_NULL" \
                        "{x}$S{b}$S{m}$S[0]$S" "4" \
                        "{x}$S{b}$S{m}$S[1]$S" "3" \
                        "{x}$S{b}$S{m}$S[2]$S" "2" \
                        "{x}$S{b}$S{m}$S[3]$S" "1"

    trie_unshift_leaf t1 "{x}$S{b}$S{m}$S" "1"
    trie_unshift_leaf t1 "{x}$S{b}$S{m}$S" "2"
    trie_unshift_leaf t1 "{x}$S{b}$S{m}$S" "3"
    trie_unshift_leaf t1 "{x}$S{b}$S{m}$S" "4"

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
    trie_inserts t1     "{a}$S{b}$S{c}$S" "1" \
                        "{a}$S{m}$S" "$TR_VALUE_NULL" \
                        "{x}$S{a1}$S{b}$S{c}$S" "1" \
                        "{x}$S{b}$S{m}$S[5]$S" "$TR_VALUE_NULL"

    local -A "t2=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_inserts t2     "{a}$S{b}$S{c}$S" "1" \
                        "{a}$S{m}$S" "$TR_VALUE_NULL" \
                        "{mxx}$S{a1}$S{b}$S{c}$S" "1" \
                        "{x}$S{b}$S{m}$S[5]$S" "$TR_VALUE_NULL"

    trie_push_tree t1 "{a}$S{x}$S{b}$S{m}$S" t2
    
    local -A "t1_spec=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_inserts t1_spec "{a}$S{b}$S{c}$S" "1" \
                        "{a}$S{m}$S" "$TR_VALUE_NULL" \
                        "{x}$S{a1}$S{b}$S{c}$S" "1" \
                        "{x}$S{b}$S{m}$S[5]$S" "$TR_VALUE_NULL" \
                        "{a}$S{x}$S{b}$S{m}$S[1]$S{a}$S{b}$S{c}$S" "1" \
                        "{a}$S{x}$S{b}$S{m}$S[1]$S{a}$S{m}$S" "$TR_VALUE_NULL" \
                        "{a}$S{x}$S{b}$S{m}$S[1]$S{mxx}$S{a1}$S{b}$S{c}$S" "1" \
                        "{a}$S{x}$S{b}$S{m}$S[1]$S{x}$S{b}$S{m}$S[5]$S" "$TR_VALUE_NULL" \
                        "{a}$S{x}$S{b}$S{m}$S[0]$S{new}$S" "new_value"


    local -A "t3=(${|trie_init "$TR_TYPE_OBJ";})"
    trie_insert t3 "{new}$S" "new_value"
    trie_unshift_tree t1 "{a}$S{x}$S{b}$S{m}$S" t3

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
    trie_inserts t1     "{a}$S" "1"                    \
                        "{b}$S" "101.3$S"              \
                        "{c}$S" "101.3"                \
                        "{d}$S" "${TR_VALUE_TRUE}"     \
                        "{e}$S" "${TR_VALUE_FALSE}"    \
                        "{f}$S" "${TR_VALUE_NULL_ARR}" \
                        "{g}$S" "${TR_VALUE_NULL_OBJ}" \
                        "{h}$S" "${TR_VALUE_NULL}"     \
                        "{i}$S" "null"                 \
                        "{j}$S" $'xxx\n  \n yyy'
    local flat_1 flat_1_ret
    local -A flat_1_spec=(
        [a]=1
        [b]="101.3$S"
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
    trie_inserts t1     "[10]$S" "1"                    \
                        "[14]$S" "101.3$S"              \
                        "[16]$S" "101.3"                \
                        "[17]$S" "${TR_VALUE_TRUE}"     \
                        "[18]$S" "${TR_VALUE_FALSE}"    \
                        "[19]$S" "${TR_VALUE_NULL_ARR}" \
                        "[20]$S" "${TR_VALUE_NULL_OBJ}" \
                        "[21]$S" "${TR_VALUE_NULL}"     \
                        "[22]$S" "null"                 \
                        "[23]$S" "xxx"
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
        "101.3$S"
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
    trie_inserts t1     "{x}$S{a}$S" "1"                    \
                        "{x}$S{b}$S" "101.3$S"              \
                        "{x}$S{c}$S" "101.3"                \
                        "{x}$S{d}$S" "${TR_VALUE_TRUE}"     \
                        "{y}$S{e}$S" "${TR_VALUE_FALSE}"    \
                        "{y}$S{f}$S" "${TR_VALUE_NULL_ARR}" \
                        "{y}$S{g}$S" "${TR_VALUE_NULL_OBJ}" \
                        "{y}$S{h}$S" "${TR_VALUE_NULL}"     \
                        "{y}$S{i}$S" "null"                 \
                        "{y}$S{j}$S" "xxx"
    local flat_1 flat_1_ret
    local -A flat_1_spec=(
        [a]=1
        [b]="101.3$S"
        [c]="101.3"
        [d]="${TR_VALUE_TRUE}"
        )
    if flat_1=${|trie_to_flat_assoc t1 "{x}$S";} ; then
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

    local xxk=${|trie_inserts t2     "[0]$S[10]$S" "1"   \
                    "[0]$S[14]$S" "101.3$S"              \
                    "[1]$S[16]$S" "101.3"                \
                    "[1]$S[17]$S" "${TR_VALUE_TRUE}"     \
                    "[1]$S[18]$S" "${TR_VALUE_FALSE}"    \
                    "[1]$S[19]$S" "${TR_VALUE_NULL_ARR}" \
                    "[1]$S[20]$S" "${TR_VALUE_NULL_OBJ}" \
                    "[1]$S[21]$S" "${TR_VALUE_NULL}"     \
                    "[1]$S[22]$S" "null"                 \
                    "[1]$S[23]$S" "xxx";}

    local xxy=${|trie_qinserts t1 leaves "[0]$S" \
                "[10]$S" "1"                     \
                "[14]$S" "101.3$S" ;}

    if [[ "$xxy" == '13 17' && "$xxk" == '13 17 35 36 37 38 39 40 41 42' ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    local xxy=${|trie_qinserts t1 leaves "[1]$S" \
                "[16]$S" "101.3"                 \
                "[17]$S" "${TR_VALUE_TRUE}"      \
                "[18]$S" "${TR_VALUE_FALSE}"     \
                "[19]$S" "${TR_VALUE_NULL_ARR}"  \
                "[20]$S" "${TR_VALUE_NULL_OBJ}"  \
                "[21]$S" "${TR_VALUE_NULL}"      \
                "[22]$S" "null"                  \
                "[23]$S" "xxx" ;}

    if [[ "$xxy" == '35 36 37 38 39 40 41 42' ]] ; then
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
        "101.3$S"
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
    trie_insert t1 "[0]$S{b}$S" "xx"
    trie_insert t1 "[1]$S{c}$S" "yy"

    local -a my_arr=("a 1" "b 2" "$TR_VALUE_NULL" "$TR_VALUE_NULL_OBJ" "$TR_VALUE_NULL_ARR")
    my_arr[10]=5
    local node_id=${|trie_flat_to_tree t1 "[0]$S{b}$S" my_arr;}

    local -A "t2=(${|trie_init "$TR_TYPE_ARR";})"
    trie_insert t2 "[0]$S{b}$S" "$TR_VALUE_NULL"
    trie_insert t2 "[1]$S{c}$S" "yy"
    trie_insert t2 "[0]$S{b}$S[0]$S" "a 1"
    trie_insert t2 "[0]$S{b}$S[1]$S" "b 2"
    trie_insert t2 "[0]$S{b}$S[2]$S" "$TR_VALUE_NULL"
    trie_insert t2 "[0]$S{b}$S[3]$S" "$TR_VALUE_NULL_OBJ"
    trie_insert t2 "[0]$S{b}$S[4]$S" "$TR_VALUE_NULL_ARR"
    trie_insert t2 "[0]$S{b}$S[10]$S" "5"

    if trie_equals t1 t2 &&
       [[ "$node_id" == "6" ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
    
    return 0
}

test_case10 ()
{
    local -A "t1=(${|trie_init "$TR_TYPE_ARR";})"
    trie_insert t1 "[0]$S{b}$S" "xx"
    trie_insert t1 "[1]$S{c}$S" "yy"

    local -A my_arr=(['key 1']='value 1' [key2]="$TR_VALUE_NULL_ARR")
    local node_id=${|trie_flat_to_tree t1 "(0)$S{b}$S" my_arr;}

    local -A "t2=(${|trie_init "$TR_TYPE_ARR";})"
    trie_insert t2 "[0]$S{b}$S{key 1}$S" "value 1"
    trie_insert t2 "[0]$S{b}$S{key2}$S" "$TR_VALUE_NULL_ARR"
    trie_insert t2 "(1)$S{c}$S" "yy"
    trie_insert t2 "(1)$S{b}$S" "xx"
    
    if [[ "$node_id" == 7 ]] &&
        trie_equals t1 t2 ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

# step_test 10
eval -- "${|AS_RUN_TEST_CASES;}"


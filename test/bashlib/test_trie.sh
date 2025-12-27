#!/usr/bin/env bash

. ../../src/bashlib/trie.sh
. ../libs/test_utils.sh


# trie_get_subtree
test_case1 ()
{
    local -A "t=(${|trie_init;})"
    trie_inserts t "lev1-1${S}lev2-1${S}lev3-1${S}" '1' \
                   "lev1-1${S}lev2-1${S}lev3-2${S}" '2' \
                   "lev1-1${S}lev2-1${S}lev3-3${S}" '3' \
                   "lev1-1${S}lev2-1${S}lev3-4${S}" '4' \
                   "lev1-1${S}lev2-1${S}lev3-5${S}" '5' \
                   "lev1-1${S}lev2-2${S}lev3-x1${S}" '6' \
                   "lev1-1${S}lev2-2${S}lev3-x2${S}" '7' \
                   "lev1-1${S}lev2-2${S}lev3-x3${S}" '8' \
                   "lev1-1${S}lev2-2${S}lev3-x4${S}" '9' \
                   "lev1-2${S}lev2-1${S}lev3-5${S}" '5' \
                   "lev1-2${S}lev2-2${S}lev3-x1${S}" '6' \
                   "lev1-2${S}lev2-2${S}lev3-x2${S}" '7' \
                   "lev1-2${S}lev2-2${S}lev3-x3${S}" '8' \
                   "lev1-2${S}lev2-2${S}lev3-x4${S}" '9' \
                   "lev1-1${S}lev2-2${S}lev3-x5${S}0${S}" '9' \
                   "lev1-1${S}lev2-2${S}lev3-x5${S}1${S}" '9' \
                   "lev1-1${S}lev2-2${S}lev3-x5${S}2${S}" '9' \
                   "lev1-1${S}lev2-2${S}lev3-x5${S}3${S}" '9' \
                   "lev1-1${S}lev2-2${S}lev3-x5${S}4${S}" '9' \
                   "lev1-1${S}lev2-2${S}lev3-x5${S}5${S}" '9' \
                   "lev1-1${S}lev2-2${S}lev3-x5${S}11${S}" '9' \
                   "lev1-1${S}lev2-2${S}lev3-x5${S}a${S}" '9'

    trie_dump t
    local get_str1=${ trie_dump_flat t;}

    # 1. 整颗树
    local -A "sub_t=(${|trie_get_subtree t;})"
    trie_dump sub_t

    # 2. 键不存在
    local sub_t_str ; sub_t_str=${|trie_get_subtree t "lev1-1${S}LEv2${S}";}
    if [[ "$?" == "$TR_RET_ENUM_KEY_IS_NOTFOUND" ]] ; then
        echo "${FUNCNAME[0]} 1 test pass."
    else
        echo "${FUNCNAME[0]} 1 test fail."
        return 1
    fi

    # 3. 键非法
    local sub_t_str ; sub_t_str=${|trie_get_subtree t "lev1-1${S}Lev2-1";}
    if [[ "$?" == "$TR_RET_ENUM_KEY_IS_NULL" ]] ; then
        echo "${FUNCNAME[0]} 2 test pass."
    else
        echo "${FUNCNAME[0]} 2 test fail."
        return 1
    fi

    # 4. 叶子键
    local sub_t_str ; sub_t_str=${|trie_get_subtree t "lev1-1${S}lev2-1${S}lev3-1${S}";}
    if [[ "$?" == "$TR_RET_ENUM_KEY_IS_LEAF" ]] ; then
        echo "${FUNCNAME[0]} 3 test pass."
    else
        echo "${FUNCNAME[0]} 3 test fail."
        return 1
    fi

    # 5.获取一级子健
    local -A "sub_t=(${|trie_get_subtree t "lev1-1${S}lev2-2${S}";})"
    diff_two_str_side_by_side "${ trie_dump t;}" "${ trie_dump sub_t;}"

    local -A "sub_t_new=(${|trie_init;})"
    trie_inserts sub_t_new "lev3-x1$S" 6 \
                           "lev3-x2$S" 7 \
                           "lev3-x3$S" 8 \
                           "lev3-x4$S" 9 \
                           "lev3-x5${S}0$S" 9 \
                           "lev3-x5${S}1$S" 9 \
                           "lev3-x5${S}2$S" 9 \
                           "lev3-x5${S}3$S" 9 \
                           "lev3-x5${S}11$S" 9 \
                           "lev3-x5${S}4$S" 9 \
                           "lev3-x5${S}5$S" 9 \
                           "lev3-x5${S}a$S" 9

    diff_two_str_side_by_side "${ trie_dump_flat sub_t_new;}" "${ trie_dump_flat sub_t;}"

    if trie_equals sub_t sub_t_new ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

test_case2 ()
{
    local -A "t1=(${|trie_init;})"
    trie_inserts t1 "a${S}b${S}11${S}" '0' \
                    "a${S}b${S}3${S}" '0' \
                    "a${S}b${S}4${S}" '0' \
                    "a${S}b${S}5${S}" '0' \
                    "a${S}b${S}1${S}" '1' \
                    "a${S}b${S}2${S}" '2' \
                    "a${S}b${S}a${S}" '2'

    trie_delete t1 "a${S}b${S}a${S}"
    
    local -A "t2=(${|trie_init;})"
    trie_inserts t2 "a${S}b${S}11${S}" '0' \
                    "a${S}b${S}3${S}" '0' \
                    "a${S}b${S}4${S}" '0' \
                    "a${S}b${S}5${S}" '0' \
                    "a${S}b${S}1${S}" '1' \
                    "a${S}b${S}2${S}" '2'

    if trie_equals t1 t2 ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

# 测试 trie_walk
test_case3 ()
{
    local -A "t1=(${|trie_init;})"
    trie_inserts t1 "a${S}b${S}11${S}" '0' \
                    "a${S}b${S}3${S}" '0' \
                    "a${S}b${S}4${S}" '0' \
                    "a${S}b${S}5${S}" '0' \
                    "a${S}b${S}1${S}" '1' \
                    "a${S}b${S}2${S}" '2' \
                    "a${S}c${S}5${S}" '0' \
                    "a${S}c${S}1${S}" '1' \
                    "a${S}c${S}2${S}" '2' \
                    "m${S}c${S}2${S}" '2' \
                    "k${S}c${S}2${S}" '2' \
                    "k${S}c${S}4${S}" '2'

    local expect_str='type:tree full_key:a node_id:2 parent:1 value:
type:tree full_key:k node_id:17 parent:1 value:
type:tree full_key:m node_id:14 parent:1 value:
type:tree full_key:m.c node_id:15 parent:14 value:
type:leaf full_key:m.c.2 node_id:16 parent:15 value:2
type:tree full_key:k.c node_id:18 parent:17 value:
type:leaf full_key:k.c.2 node_id:19 parent:18 value:2
type:leaf full_key:k.c.4 node_id:20 parent:18 value:2
type:tree full_key:a.b node_id:3 parent:2 value:
type:tree full_key:a.c node_id:10 parent:2 value:
type:leaf full_key:a.c.1 node_id:12 parent:10 value:1
type:leaf full_key:a.c.2 node_id:13 parent:10 value:2
type:leaf full_key:a.c.5 node_id:11 parent:10 value:0
type:leaf full_key:a.b.1 node_id:8 parent:3 value:1
type:leaf full_key:a.b.2 node_id:9 parent:3 value:2
type:leaf full_key:a.b.3 node_id:5 parent:3 value:0
type:leaf full_key:a.b.4 node_id:6 parent:3 value:0
type:leaf full_key:a.b.5 node_id:7 parent:3 value:0
type:leaf full_key:a.b.11 node_id:4 parent:3 value:0'
    
    local get_str=${ trie_walk t1;}
    if [[ "$get_str" == "$expect_str" ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
    return 0
}

# 测试 trie_iter
test_case4 ()
{
    local -A "t1=(${|trie_init;})"
    trie_insert t1 "a${S}b${S}1xx1$S" '0'
    trie_insert t1 "a${S}b${S}d  g3$S" '0'
    trie_insert t1 "a${S}b${S}4$S" '0  gege'
    trie_insert t1 "a${S}b${S}5$S" '0'
    trie_insert t1 "a${S}b${S}1$S" '1 geg中文'
    trie_insert t1 "a${S}b${S}a中文 budv不对2$S" '2'
    trie_insert t1 "m${S}b${S}2$S" '2'
    trie_insert t1 "c${S}bgege
    gege
${S}中文2$S" '2
gege
geg'
    trie_insert t1 "c${S}k$S" 'value2 xx 3'
    trie_insert t1 "c${S}k 78$S" 'valuex yy 3'

    trie_dump t1

    local OLD_IFS="$IFS"
    local IFS=$'\n'
    local tuple type token value node

    local -a get_arr=()
    local -a expect_arr=(
        [0]="1" [1]="leaf"
        [2]="1xx1" [3]="leaf"
        [4]="4" [5]="leaf"
        [6]="5" [7]="leaf"
        [8]="a中文 budv不对2" [9]="leaf"
        [10]="d  g3" [11]="leaf"
        [12]=$'bgege\n    gege\n' [13]="tree"
        [14]="k" [15]="leaf"
        [16]="k 78" [17]="leaf"

        [18]=$'bgege\n    gege\n' [19]="tree" [20]="" [21]="14"
        [22]="k" [23]="leaf" [24]="value2 xx 3" [25]="16"
        [26]="k 78" [27]="leaf" [28]="valuex yy 3" [29]="17"
        
        [30]=$'bgege\n    gege\n' [31]="tree" [32]=""
        [33]="k" [34]="leaf" [35]="value2 xx 3"
        [36]="k 78" [37]="leaf" [38]="valuex yy 3"
        
        [39]=$'bgege\n    gege\n' [40]="tree" [41]="14"
        [42]="k" [43]="leaf" [44]="16"
        [45]="k 78" [46]="leaf" [47]="17")


    for tuple in ${|trie_iter t1 "a${S}b${S}";} ; do
        eval -- set -- $tuple
        token=$1 type=$2 
        get_arr+=("$token" "$type")
    done

    for tuple in ${|trie_iter t1 "c$S";} ; do
        eval -- set -- $tuple
        token=$1 type=$2
        get_arr+=("$token" "$type")
    done

    for tuple in ${|trie_iter t1 "c$S" $((2#1111));} ; do
        eval -- set -- $tuple
        token=$1 type=$2 value=$3 node=$4
        get_arr+=("$token" "$type" "$value" "$node")
    done

    for tuple in ${|trie_iter t1 "c$S" $((2#0111));} ; do
        eval -- set -- $tuple
        token=$1 type=$2 value=$3
        get_arr+=("$token" "$type" "$value")
    done

    for tuple in ${|trie_iter t1 "c$S" $((2#1011));} ; do
        eval -- set -- $tuple
        token=$1 type=$2 node=$3
        get_arr+=("$token" "$type" "$node")
    done

    if assert_array 'a' get_arr expect_arr ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

# test _split_tokens
test_case5 ()
{
    local my_str=" ggeege
gege${S} xxx xyy ${S} ggge ge
28338*()${S}"
    local -a "my_arr=(${|_split_tokens "$my_str";})"

    local -a ret_arr=(
        [0]=$' ggeege\ngege'
        [1]=" xxx xyy "
        [2]=$' ggge ge\n28338*()'
    )
    
    if assert_array 'a' my_arr ret_arr ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

# 测试 trie_equals
test_case6 ()
{
    local -A "t1=(${|trie_init;})"
    local -A "t2=(${|trie_init;})"

    # 1. 两颗根树应该相等
    if trie_equals t1 t2 ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
    
    # 2. 增加不同样的三个叶子
    trie_insert t1 "a${S}b${S}c${S}" 'v1'
    trie_insert t1 "a${S}b${S}d${S}" 'v2'
    trie_insert t1 "a${S}b${S}e${S}" 'v3'
    trie_delete t1 "a${S}b${S}e${S}"
    trie_delete t1 "a${S}b${S}d${S}"
    trie_insert t1 "a${S}b${S}e${S}" 'v3'
    trie_insert t1 "a${S}b${S}d${S}" 'v2'

    trie_insert t2 "a${S}b${S}c${S}" 'v1'
    trie_insert t2 "a${S}b${S}d${S}" 'v2'
    trie_insert t2 "a${S}b${S}e${S}" 'v3'
    trie_insert t2 "a${S}b${S}x${S}" 'v3'

    diff_two_str_side_by_side "${ trie_dump t1;}" "${ trie_dump t2;}"

    if ! trie_equals t1 t2 ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

    trie_delete t2 "a${S}b${S}x${S}"

    if trie_equals t1 t2 ; then
        log_test 1 3
    else
        log_test 0 3 ; return 1
    fi

    # 增加更深的层级
    trie_insert t1 "a${S}x y${S}1${S}" 'v2'
    trie_insert t1 "a${S}x y${S}2${S}" 'v562'

    trie_insert t2 "a${S}x y${S}1${S}" 'v2'
    trie_insert t2 "a${S}x y${S}2${S}" 'v562'

    if trie_equals t1 t2 ; then
        log_test 1 4
    else
        log_test 0 4 ; return 1
    fi
}

# trie_dump_flat
test_case7 ()
{
    local -A "mytree=(${|trie_init;})"
    trie_inserts mytree "a${S}b${S}c$S" 'value1' \
                        "a${S}b${S}x$S" 'value2' \
                        "a${S}m$S" 'value3' \
                        "a${S}k${S}0$S" 'value4' \
                        "a${S}k${S}1$S" 'value5' \
                        "a${S}k${S}2$S" 'value6' \
                        "a${S}k${S}3$S" 'value7' \
                        "a${S}k${S}4${S}key1$S" 'value8' \
                        "a${S}k${S}4${S}key2$S" 'value9' \
                        "b${S}" 'value10'
    
    local get_str1=${ trie_dump_flat 'mytree';}
    local get_str2=${ trie_dump_flat 'mytree' "a${S}";}
    local get_str3=${ trie_dump_flat 'mytree' "a$S" 4 $((2#0));}
    local get_str4=${ trie_dump_flat 'mytree' "a$S" 4 $((2#1));}

    local str1_spec='mytree
    1 => 1
    1.children => a.b
    1.child.a => 2
    1.child.b => 15
    15 => 1
    15.key => b => value10
    2 => 1
    2.children => b.k.m
    2.child.b => 3
    2.child.k => 7
    2.child.m => 6
    6 => 1
    6.key => a.m => value3
    7 => 1
    7.children => 0.1.2.3.4
    7.child.0 => 8
    7.child.1 => 9
    7.child.2 => 10
    7.child.3 => 11
    7.child.4 => 12
    12 => 1
    12.children => key1.key2
    12.child.key1 => 13
    12.child.key2 => 14
    14 => 1
    14.key => a.k.4.key2 => value9
    13 => 1
    13.key => a.k.4.key1 => value8
    11 => 1
    11.key => a.k.3 => value7
    10 => 1
    10.key => a.k.2 => value6
    9 => 1
    9.key => a.k.1 => value5
    8 => 1
    8.key => a.k.0 => value4
    3 => 1
    3.children => c.x
    3.child.c => 4
    3.child.x => 5
    5 => 1
    5.key => a.b.x => value2
    4 => 1
    4.key => a.b.c => value1
    max_index => 16'
   
    local str2_spec='mytree
    2 => 1
    2.children => b.k.m
    2.child.b => 3
    2.child.k => 7
    2.child.m => 6
    6 => 1
    6.key => a.m => value3
    7 => 1
    7.children => 0.1.2.3.4
    7.child.0 => 8
    7.child.1 => 9
    7.child.2 => 10
    7.child.3 => 11
    7.child.4 => 12
    12 => 1
    12.children => key1.key2
    12.child.key1 => 13
    12.child.key2 => 14
    14 => 1
    14.key => a.k.4.key2 => value9
    13 => 1
    13.key => a.k.4.key1 => value8
    11 => 1
    11.key => a.k.3 => value7
    10 => 1
    10.key => a.k.2 => value6
    9 => 1
    9.key => a.k.1 => value5
    8 => 1
    8.key => a.k.0 => value4
    3 => 1
    3.children => c.x
    3.child.c => 4
    3.child.x => 5
    5 => 1
    5.key => a.b.x => value2
    4 => 1
    4.key => a.b.c => value1
    max_index => 16'

    local str3_spec='mytree
    2 => 1
    2.children => b.k.m
    2.child.b => 3
    2.child.k => 7
    2.child.m => 6
    6 => 1
    6.key => a.m => 
    7 => 1
    7.children => 0.1.2.3.4
    7.child.0 => 8
    7.child.1 => 9
    7.child.2 => 10
    7.child.3 => 11
    7.child.4 => 12
    12 => 1
    12.children => key1.key2
    12.child.key1 => 13
    12.child.key2 => 14
    14 => 1
    14.key => a.k.4.key2 => 
    13 => 1
    13.key => a.k.4.key1 => 
    11 => 1
    11.key => a.k.3 => 
    10 => 1
    10.key => a.k.2 => 
    9 => 1
    9.key => a.k.1 => 
    8 => 1
    8.key => a.k.0 => 
    3 => 1
    3.children => c.x
    3.child.c => 4
    3.child.x => 5
    5 => 1
    5.key => a.b.x => 
    4 => 1
    4.key => a.b.c => 
    max_index => 16'

    if  [[ "$get_str1" == "$str1_spec" ]] &&
        [[ "$get_str2" == "$str2_spec" ]] &&
        [[ "$get_str3" == "$str3_spec" ]] &&
        [[ "$get_str4" == "$str2_spec" ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
    
    return 0
}

# trie_dump
test_case8 ()
{
    local -A "mytree=(${|trie_init;})"
    trie_inserts mytree "a${S}b${S}c${S}" "value1" \
                        "a${S}b${S}e
gege
${S}" "value2" \
                        "a${S}b${S}f${S}" "valgege
gege
ue3" \
                        "a${S}c${S}0${S}" "value4" \
                        "a${S}c${S}1
ge
geg${S}" "value
gege
g5" \
                        "a${S}c${S}2${S}" "value6" \
                        "a${S}c${S}3${S}" "value7" \
                        "a${S}c${S}4${S}" "value8" \
                        "a${S}c${S}5${S}" "value9"
    local dump_str1=${ trie_dump mytree;}
    local dump_str2=${ trie_dump mytree '' 4 $((2#10));}
    local dump_str3=${ trie_dump mytree '' 4 $((2#01));}
    local dump_str4=${ trie_dump mytree '' 4 $((2#00));}
    local dump_str5=${ trie_dump mytree '' 4 $((2#11));}

    local dump_spec1='mytree
    a(2)
        b(3)
            e
            gege
            (5) => value2
            c(4) => value1
            f(6) => valgege
                    gege
                    ue3
        c(7)
            1
            ge
            geg(9) => value
                      gege
                      g5
            0(8) => value4
            2(10) => value6
            3(11) => value7
            4(12) => value8
            5(13) => value9
    max_index => 14'
    local dump_spec2='mytree
    a
        b
            e
            gege
             => value2
            c => value1
            f => valgege
                 gege
                 ue3
        c
            1
            ge
            geg => value
                   gege
                   g5
            0 => value4
            2 => value6
            3 => value7
            4 => value8
            5 => value9
    max_index => 14'
    local dump_spec3='mytree
    a(2)
        b(3)
            e
            gege
            (5) => 
            c(4) => 
            f(6) => 
        c(7)
            1
            ge
            geg(9) => 
            0(8) => 
            2(10) => 
            3(11) => 
            4(12) => 
            5(13) => 
    max_index => 14'
    local dump_spec4='mytree
    a
        b
            e
            gege
             => 
            c => 
            f => 
        c
            1
            ge
            geg => 
            0 => 
            2 => 
            3 => 
            4 => 
            5 => 
    max_index => 14'
    local dump_spec5='mytree
    a(2)
        b(3)
            e
            gege
            (5) => value2
            c(4) => value1
            f(6) => valgege
                    gege
                    ue3
        c(7)
            1
            ge
            geg(9) => value
                      gege
                      g5
            0(8) => value4
            2(10) => value6
            3(11) => value7
            4(12) => value8
            5(13) => value9
    max_index => 14'
    if [[ "$dump_str1" == "$dump_spec1" ]] &&
        [[ "$dump_str2" == "$dump_spec2" ]] &&
        [[ "$dump_str3" == "$dump_spec3" ]] &&
        [[ "$dump_str4" == "$dump_spec4" ]] &&
        [[ "$dump_str5" == "$dump_spec5" ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
    
    return 0
}

# step_test 8
eval -- "${|AS_RUN_TEST_CASES;}"


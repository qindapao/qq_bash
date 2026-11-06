#!/usr/bin/env bash

. ../../src/bashlib/array.sh
. ../libs/test_utils.sh

test_case1 ()
{
    local TestCase1_arr=(1 2 3 4 6)
    local value=5
    array_sorted_insert TestCase1_arr "$value" '-gt'
    if [[ "${TestCase1_arr[*]}" == "1 2 3 4 5 6" ]] ; then
        echo "${FUNCNAME[0]} test pass."
    else
        echo "${FUNCNAME[0]} test fail."
        return 1
    fi
    return 0
}

test_case2 ()
{
    local TestCase2_arr=(10 9 7 6 5 4 2 1)
    local value=2
    array_sorted_insert TestCase2_arr "$value" '-lt'
    if [[ "${TestCase2_arr[*]}" == "10 9 7 6 5 4 2 2 1" ]] ; then
        echo "${FUNCNAME[0]} test pass."
    else
        echo "${FUNCNAME[0]} test fail."
        return 1
    fi
    return 0
}

test_case3 ()
{
    local TestCase3_arr=(a b c f g)
    local value=e
    array_sorted_insert TestCase3_arr "$value" '>'
    if [[ "${TestCase3_arr[*]}" == "a b c e f g" ]] ; then
        echo "${FUNCNAME[0]} test pass."
    else
        echo "${FUNCNAME[0]} test fail."
        return 1
    fi
    return 0
}

test_case4 ()
{
    local TestCase4_arr=(g f b a)
    local value=d
    array_sorted_insert TestCase4_arr "$value" '<'
    if [[ "${TestCase4_arr[*]}" == "g f d b a" ]] ; then
        echo "${FUNCNAME[0]} test pass."
    else
        echo "${FUNCNAME[0]} test fail."
        return 1
    fi
    return 0
}

test_case6 ()
{
    local -
    # set -x
    local TestCase6_a=(1 2 "a 3" 4 5 "a 3" 6)
    local e="a 3"
    array_delete_first_e TestCase6_a "$e"
    local TestCase6_a_spec=(
    1 2 
    [3]=4
    5 "a 3" 6)

    if assert_array a TestCase6_a TestCase6_a_spec ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    local TestCase6_a=(1 2 "a 3" 4 5 "a 3" 6)
    array_delete_e TestCase6_a "$e"
    local TestCase6_a_spec=(
    1 2 
    [3]=4
    5
    [6]=6)

    if assert_array a TestCase6_a TestCase6_a_spec ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

    return 0
}

test_case7 ()
{
    local -a ori_arr=(
        "{CLASS}"
        "{CNT}"
        "{cut_plus}"
        "{haha}"
        "{P1}"
        "{P2}"
        "{print_self}"
        "{SELF}"
        "{SUPER}"
        )
    local -a sort_arr=()
    local -a spec_arr=(
        "{print_self}"
        "{haha}"
        "{cut_plus}"
        "{SUPER}"
        "{SELF}"
        "{P2}"
        "{P1}"
        "{CNT}"
        "{CLASS}"
    )

    local item
    for item in "${ori_arr[@]}" ; do
        array_sorted_insert sort_arr "$item" '<'
    done

    if assert_array a sort_arr spec_arr ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

test_case8 ()
{
    local -a ori_arr=(
        "c"
        "c2"
        "c1"
        )
    local -a sort_arr=()
    local -a spec_arr=(
        "c2"
        "c1"
        "c"
        )

    local item
    for item in "${ori_arr[@]}" ; do
        array_sorted_insert sort_arr "$item" '<'
    done

    if assert_array a sort_arr spec_arr ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

test_case9 ()
{
    local a1=()
    local str1=''
    local str2='x b'
    local a2=('a 2 c  ' '1 2 3 ' 'degeg' '中文')

    array_join a1 "str1"  ; local join1=$REPLY
    array_join a1 "str2"  ; local join2=$REPLY
    array_join a2 "$str1" ; local join3=$REPLY
    array_join a2 "$str2" ; local join4=$REPLY

    if [[ "$join1" == '' ]] &&
        [[ "$join2" == '' ]] &&
        [[ "$join3" == 'a 2 c  1 2 3 degeg中文' ]] &&
        [[ "$join4" == 'a 2 c  x b1 2 3 x bdegegx b中文' ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

eval -- "$(AS_RUN_TEST_CASES)"


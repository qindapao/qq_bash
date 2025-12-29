#!/usr/bin/env bash

. ../libs/test_utils.sh

. ../../src/bashlib/float.sh

test_case1 ()
{
    local -a arr_xx=(1 2 3 4 5 6)
    local i=3
    local -a arr_xx=("${arr_xx[@]:0:$i}" "a" "${arr_xx[@]:$i}")
    local -a arr_spec=(1 2 3 a 4 5 6)
    if assert_array 'a' arr_xx arr_spec ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

test_case2 ()
{
    local -a arr_xx=({1..50000})
    local start=$EPOCHREALTIME
    arr_xx=("${arr_xx[@]:0:10000}" "new_element" "${arr_xx[@]:10000}")
    local end=$EPOCHREALTIME
    elapsed=$(awk -v s="$start" -v e="$end" 'BEGIN {print (e - s) * 1000}')
    # time is less than 300 ms
    if float_compare "300" "$elapsed" ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

eval -- "${|AS_RUN_TEST_CASES;}"


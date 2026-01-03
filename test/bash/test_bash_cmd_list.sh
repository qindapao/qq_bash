#!/usr/bin/env bash

. ../libs/test_utils.sh

test_case1 ()
{
    local a=1 b=2
    local c
    [[ "$a" == "1" ]] && {
        false
        c=2
    }

    if [[ "$c" == 2 ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    false || c=3
    true && c=4

    if [[ "$c" == 4 ]] ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi
    
    return 0
}

test_case2 ()
{
    local a=1 b=2 c=3
    local m1 m2

    [[  "$a" == 1 &&
        ("$b" == 2 ||
        "$c" == 4) ]] && {
        m1=1
    }

    [[ "$a" == 1 ]] &&
    [[ "$b" == 2 ]] &&
    [[ "$c" == 3 ]] && {
        m2=1
    }

    if [[ "$m1" == 1 ]] && [[ "$m2" == 1 ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

eval -- "${|AS_RUN_TEST_CASES;}"



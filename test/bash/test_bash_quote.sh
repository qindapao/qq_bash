#!/usr/bin/env bash

. ../libs/test_utils.sh

test_case1 ()
{
    local a=$'gge geg gege' m k
    printf -v m "%q" "$a"
    k=${a@Q}

    if [[ "$m" == "$k" ]] ; then
        log_test 0 1 ; return 1
    else
        log_test 1 1
    fi

    eval -- "m_after=$m"
    eval -- "k_after=$k"

    if [[ "$m_after" == "$k_after" ]] ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

    return 0
}

eval -- "${|AS_RUN_TEST_CASES;}"


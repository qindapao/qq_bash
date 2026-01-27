#!/usr/bin/env bash

. ../libs/test_utils.sh

test_case1 ()
{
    local a=1
    for((;;)) ; do
        ((a++))
        ((a==4)) && break
    done
    if ((a==4)) ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}


eval -- "$(AS_RUN_TEST_CASES)"


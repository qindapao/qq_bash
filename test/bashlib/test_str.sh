#!/usr/bin/env bash

. ../../src/bashlib/str.sh
. ../libs/test_utils.sh

test_case1 ()
{
    local demo_str='*1*a*b'
    local str_count=${|str_count "$demo_str" '*';}
    if [[ "$str_count" == '3' ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    local demo_str="我是中文hahah中文文"
    local str_count=${|str_count "$demo_str" '中文';}
    if [[ "$str_count" == '2' ]] ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

    local demo_str="我是中文hahah中文文"
    local str_count=${|str_count "$demo_str" '中x文';}
    if [[ "$str_count" == '0' ]] ; then
        log_test 1 3
    else
        log_test 0 3 ; return 1
    fi

    local demo_str=""
    local str_count=${|str_count "$demo_str" '中x文';}
    if [[ "$str_count" == '-1' ]] ; then
        log_test 1 4
    else
        log_test 0 4 ; return 1
    fi

    return 0
}

eval -- "${|AS_RUN_TEST_CASES;}"


#!/usr/bin/env bash

. ../libs/test_utils.sh

# eval 和参数扩展
test_case1 ()
{
    local i=0 j=50
    local x=0
    eval -- '
        for x in {'$i'..'$j'} ; do
            ((x++))
        done
    '
    if [[ "$x" == "51" ]] ; then
        log_test 1 1
    else
        log_test 1 0 ; return 1
    fi
    return 0
}

eval -- "$AS_RUN_TEST_CASES"


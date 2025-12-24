#!/usr/bin/env bash

. ../libs/test_utils.sh

# eval 和参数扩展
test_case1 ()
{
    local i=0 j=50
    local x
    eval -- '
        for x in {'$i'..'$j'} ; do
            echo "$x"
        done
    '
}

eval -- "$AS_RUN_TEST_CASES"


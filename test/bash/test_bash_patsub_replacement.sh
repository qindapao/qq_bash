#!/usr/bin/env bash

. ../libs/test_utils.sh

# patsub_replacement 是匹配一个模式
test_case1 ()
{
    (
        shopt -s patsub_replacement
        s="abc123xyz"
        if [[ "$s" == '[abc123xyz]' ]] ; then
            log_test 0 1
        else
            log_test 1 1 ; return 1
        fi
    )
}

eval -- "$(AS_RUN_TEST_CASES)"


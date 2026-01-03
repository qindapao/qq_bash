#!/usr/bin/env bash

. ../libs/test_utils.sh

test_case1 ()
{
    test_case1_inner1 ()
    {
        local a=$1
        local b=$2
        local c=$3
        if  [[ "$a" == tr_t ]] &&
            [[ "$b" == 'other 1' ]] &&
            [[ "$c" == 'other 2' ]] ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi

        return 0
    }


    # There cannot be quotation marks in the parameters of my_cmd
    local my_cmd='test_case1_inner1 tr_t'
    $my_cmd "other 1" "other 2" || return $?

    return 0
}

eval -- "${|AS_RUN_TEST_CASES;}"



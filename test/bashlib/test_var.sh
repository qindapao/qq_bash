#!/usr/bin/env bash

. ../../src/bashlib/var.sh
. ../libs/test_utils.sh

test_case1 ()
{
    local bitmap=$((2#1111111))
    local a b c

    var_bitmap_unpack "$bitmap" a:0 b:1 c:2

    if  [[ "$a" == 1 ]] &&
        [[ "$b" == 1 ]] &&
        [[ "$c" == 1 ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    local bitmap=$((2#0101110))

    var_bitmap_unpack "$bitmap" a:0 b:4 c:6 d:2 e:1
    if  [[ "$a" == 0 ]] &&
        [[ "$b" == 0 ]] &&
        [[ "$c" == 0 ]] &&
        [[ "$d" == 1 ]] &&
        [[ "$e" == 1 ]] ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi
}

eval -- "${|AS_RUN_TEST_CASES;}"


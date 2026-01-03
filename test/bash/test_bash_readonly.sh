#!/usr/bin/env bash

. ../libs/test_utils.sh

readonly only_read_var=1

# 只读变量无法局部化
test_case1 ()
{
    local only_read_var=2 2>/dev/null
    if (($?)) ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

eval -- "${|AS_RUN_TEST_CASES;}"



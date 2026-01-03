#!/usr/bin/env bash

. ../libs/test_utils.sh

# 使用 source 执行代码的速度最慢
# eval 慢了一点点，但是还可以接受
test_case1 ()
{
    local my_code='echo "hello world!" >/dev/null'
    local i

    for i in {0..1000} ; do
        eval -- "$my_code" 
    done

    for i in {0..1000} ; do
        source /dev/stdin <<<"$my_code"
    done

    for i in {0..1000} ; do
        echo "hello world!" >/dev/null
    done
    log_test 1 1
    return 0
}

eval -- "${|AS_RUN_TEST_CASES;}"


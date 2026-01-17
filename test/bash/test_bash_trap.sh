#!/usr/bin/env bash

. ../libs/test_utils.sh

# trap 不会向上传递，只会触发一次，子函数返回也不会触发
test_case1 ()
{
    local count=0
    test_case1_inner1 ()
    {
        echo "test_case1_inner1 called."
        local my_trap_str="trap trigger"
        trap 'echo "$my_trap_str"' RETURN
        trap '((count++))' RETURN

        test_case1_inner1_inner1 ()
        {
            echo "test_case1_inner1_inner1 called."
            return
        }
        test_case1_inner1_inner1
        return 42
    }


    test_case1_inner1
    local ret_code=$?
    if ((count==1 && ret_code==42)) ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

eval -- "${|AS_RUN_TEST_CASES;}"



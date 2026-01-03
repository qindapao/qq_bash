#!/usr/bin/env bash

. ../libs/test_utils.sh

# 双圆括号中可以使用逗号表达式
test_case1 ()
{
    local a b
    for((a=1,b=1;a<=3;a++,b++)) ; do
        :
    done

    if [[ "$a" == 4 && "$b" == 4 ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

# 在 if 后面的双圆括号中是可以进行赋值操作的
# 但是这在大部分的情况下没有意义
test_case2 ()
{
    local a=1

    if ((a=0)) ; then
        log_test 0 1 ; return 1
    else
        log_test 1 1
    fi

    if ((a==0)) ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

    if ((a=2)) ; then
        if ((a==2)) ; then
            log_test 1 3
        else
            log_test 0 3 ; return 1
        fi
    fi

    if ((a==2)) ; then
        log_test 1 4
    else
        log_test 0 4 ; return 1
    fi

    test_case2_innner ()
    {
        REPLY=$((9+1))
    }

    # 双圆括号中可以执行命令，但是命令的返回值必须是整数，不然就会出现语法错误
    if ((a=${|test_case2_innner;})) ; then
        :
    fi

    if ((a==10)) ; then
        log_test 1 5
    else
        log_test 0 5 ; return 1
    fi

    return 0
}

eval -- "${|AS_RUN_TEST_CASES;}"



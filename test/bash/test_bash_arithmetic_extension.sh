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
        echo "$((9+1))"
    }

    # 双圆括号中可以执行命令，但是命令的返回值必须是整数，不然就会出现语法错误
    if ((a=$(test_case2_innner))) ; then
        :
    fi

    if ((a==10)) ; then
        log_test 1 5
    else
        log_test 0 5 ; return 1
    fi

    return 0
}

# 关联数组的键扩增安全用法(bash5.2以上其它)
# let 'assoc[$var]++'
# assoc[$var]=$(( ${assoc[$var]} + 1 ))
# ref='assoc[$var]'; (( $ref++ ))
test_case3 ()
{

    declare -A assoc=([$'gege\t \n tgeg223 \n tt223(xx:yy)xxx xxx->xx \\ * @ xx->xxx->xx:xx.x->(x \\ * @ xx:xx)->(xxxxx:xxxx)zy\n\t 133']="1" )
    declare -A assoc_spec=()
    declare x=$'zy\n\t 133'
    declare m=$'xxx xxx->xx \\ * @ xx->xxx->xx:xx.x->(x \\ * @ xx:xx)->(xxxxx:xxxx)'
    declare k='(xx:yy)'
    declare n=$'gege\t \n tgeg223 \n tt223'
    declare var=$n$k$m$x

    local -i expected=3004

    # bash 5.2 已经正常, bash4.4/5.0/5.1 的算术下标会再次解析 key，跳过
    if ((BASH_VERSINFO[0] > 5 ||
         (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 2))) ; then
        time {
        for i in {0..1000} ; do
            (( assoc[$var]++ ))
        done
        }
        expected=4005
    fi

    # 下面三种方法是安全的
    time {
        for i in {0..1000} ; do
            let 'assoc[$var]++'
        done
    }

    time {
        for i in {0..1000} ; do
            assoc[$var]=$(( ${assoc[$var]} + 1 ))
        done
    }

    time {
        for i in {0..1000} ; do
            local ref='assoc[$var]'; (( $ref++ ))
        done
    }

    assoc_spec[$var]=$expected

    if assert_array A assoc assoc_spec ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

eval -- "$(AS_RUN_TEST_CASES)"



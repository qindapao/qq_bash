#!/usr/bin/env bash

# assoc_expand_once
. ../libs/test_utils.sh

# 关联数组的赋值
# - 中括号中的元素使用 "" 保护(推荐使用)
# - 不能使用 ''，使用 '' 会被当成字面量
# - 不加 "" 保护也没有问题
test_case1 ()
{
    declare -A A
    A[key]=value
    local x='$y' y='key'

    A["$x"]='key2'

    local -A A1=([key]="value" ["\$y"]="key2" )

    if assert_array 'A' A A1 ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    A['$x']='key3'
    local -A A2=([key]="value" ["\$y"]="key2" ["\$x"]="key3" )

    if assert_array 'A' A A2 ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

    A[$x]='key4'
    local -A A3=([key]="value" ["\$y"]="key4" ["\$x"]="key3" )
    if assert_array 'A' A A3 ; then
        log_test 1 3
    else
        log_test 0 3 ; return 1
    fi

    A[* *]='key5'
    A[*]='key6'
    local -A A4=(["*"]="key6" ["* *"]="key5" [key]="value" ["\$y"]="key4" ["\$x"]="key3" )
    if assert_array 'A' A A4 ; then
        log_test 1 4
    else
        log_test 0 4 ; return 1
    fi
    
    return 0
}

# 关联数组的键存在性判断
# - 外部使用 '' 保护，并不会当成字面量(推荐使用)
# - 中括号中可以使用 "" 保护，也可以不使用(推荐使用)
# - 不加任何引号保护现在也没有问题
test_case2 ()
{
    local a='*' b="x y z ]" c='@'
    local -A A=(["x y z ]"]=1 ['*']=2 ['@']=3)

    if [[ -v A[$a] ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    if [[ -v 'A[$a]' ]] ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

    if [[ -v 'A["$a"]' ]] ; then
        log_test 1 3
    else
        log_test 0 3 ; return 1
    fi

    if [[ -v A[$b] ]] ; then
        log_test 1 4
    else
        log_test 0 4 ; return 1
    fi

    if [[ -v 'A[$b]' ]] ; then
        log_test 1 5
    else
        log_test 0 5 ; return 1
    fi

    if [[ -v 'A["$b"]' ]] ; then
        log_test 1 6
    else
        log_test 0 6 ; return 1
    fi

    if [[ -v 'A["$c"]' ]] ; then
        log_test 1 7
    else
        log_test 0 7 ; return 1
    fi

    return 0
}

# 测试关联数组键索引速度
# msys2 环境测试，实际Linux环境可能性能更好，但是比C语言要慢100倍，2个数量级
# 10万个键, 平均插入速度 10us 一个
# 50万个键，平均插入速度 15us 一个
test_case3 ()
{
    local -A A KEYS
    local start i key

    # 插入 100000 个键值对
    for i in {1..1000} ; do
        KEYS["$i"]=${|rand_str;}
    done

    # 获取开始时间
    start=$EPOCHREALTIME

    for i in {1..1000} ; do
        A["${KEYS["$i"]}"]=$i
    done

    # 获取结束时间
    end=$EPOCHREALTIME

    # 计算耗时（毫秒）
    elapsed=$(awk -v s="$start" -v e="$end" 'BEGIN {print (e - s) * 1000}')

    # 如果时间超过 15 ms,认为测试失败
    if [[ "${elapsed%%'.'*}" -gt 15 ]] ; then
        log_test 0 1 ; return 1
    else
        log_test 1 0
    fi

    return 0
}

# 测试复制关联数组到关联数组的复制操作
# 数组的情况和关联数组基本相同
# 推荐的方法:
# local -A "demo_ret=(${|test_case_temp_func2;})"
# local -A "k2=(${AS_DICT_TEMP[*]@K})"
test_case4 ()
{
    # 这个可以
    eval -- local -A k1=(${AS_DICT_TEMP[*]@K})
    # 这个可以
    local -A "k2=(${AS_DICT_TEMP[*]@K})"

    if assert_array 'A' AS_DICT_TEMP k1 k2 ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    local save_func=${|save_func test_case_temp_func;}
    test_case_temp_func ()
    {
        local -A "recive_dict1=($1)"
        eval -- local -A recive_dict2=($1)
        
        assert_array 'A' recive_dict1 recive_dict2
    }
    if test_case_temp_func "${AS_DICT_TEMP[*]@K}" ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

    unset -f test_case_temp_func
    [[ -n "$save_func" ]] && eval -- "$save_func"

    test_case_temp_func2 ()
    {
        local -A demo=(['1 2 3']=1 ['x y z']=2)
        REPLY=${demo[*]@K}
    }

    local -A demo2=(['1 2 3']=1 ['x y z']=2)
    local -A "demo_ret=(${|test_case_temp_func2;})"

    if assert_array 'A' demo2 demo_ret ; then
        log_test 1 3
    else
        log_test 0 3 ; return 1
    fi

    test_case_temp_func3 ()
    {
        local -a ademo=('1 2 3' 'x y z')
        REPLY=${ademo[*]@Q}
    }

    local -a ademo2=('1 2 3' 'x y z')
    local -a "ademo_ret=(${|test_case_temp_func3;})"
    if assert_array 'a' ademo2 ademo_ret ; then
        log_test 1 4
    else
        log_test 0 4 ; return 1
    fi

    test_case_temp_func4 ()
    {
        local -a bdemo=("$1" "$2")
        REPLY=${bdemo[*]@Q}
    }

    local -a bdemo2=('1 2 3' 'x y z')
    local -i i=0 j=1
    local -a "bdemo_ret=(${|test_case_temp_func4 "${bdemo2["$i"]}" "${bdemo2["$j"]}";})"
    if assert_array 'a' bdemo2 bdemo_ret ; then
        log_test 1 5
    else
        log_test 0 5 ; return 1
    fi

    return 0
}

# 关联数组下标赋值中的字符串拼接
test_case5 ()
{
    local -A dict=()
    local k='(xx:yy)'
    local m='xxx xxx->xxx->xxx->xx:xx.x->(xxx:xx)->(xxxxx:xxxx)'
    local x=$'zy\n\t 133'
    dict[$k$m$x]=1
    declare -A dict_spec=([$'(xx:yy)xxx xxx->xxx->xxx->xx:xx.x->(xxx:xx)->(xxxxx:xxxx)zy\n\t 133']="1" )
    if assert_array A dict dict_spec ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
    return 0
}

test_case6 ()
{
    test_case6_inner ()
    {
        local -a get_param=("$@")
        local -a get_param_spec=('1 2' 'a b' '3 4' 'c d')
        if assert_array a get_param get_param_spec ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi
    }
    local -A assoc=(['1 2']='a b' ['3 4']='c d')
    test_case6_inner "${assoc[@]@k}"
}

eval -- "${|AS_RUN_TEST_CASES;}"


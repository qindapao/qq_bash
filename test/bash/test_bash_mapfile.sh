#!/usr/bin/env bash

. ../libs/test_utils.sh

test_case1 ()
{
    local arr=()

    flush()
    {
        local line_num=$1
        printf "line_num:%s\n" "$line_num"
        printf "len:%s\n" "${#arr[@]}"
        printf "array indexes:"
        printf "%s," "${!arr[@]}"
        echo 
        printf "array elements:"
        printf "%s," "${arr[@]}"
        echo 
        arr=()
    }

    local get_str=${ mapfile -t -C flush -c 5 arr < <(printf "%s\n" {0..20});}

    local get_str_spec='line_num:4
len:4
array indexes:0,1,2,3,
array elements:0,1,2,3,
line_num:9
len:5
array indexes:4,5,6,7,8,
array elements:4,5,6,7,8,
line_num:14
len:5
array indexes:9,10,11,12,13,
array elements:9,10,11,12,13,
line_num:19
len:5
array indexes:14,15,16,17,18,
array elements:14,15,16,17,18,'

    # 后面的行会漏掉，需要单独处理下
    if [[ "$get_str" == "$get_str_spec" ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

eval -- "${|AS_RUN_TEST_CASES;}"



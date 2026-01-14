#!/usr/bin/env bash

. ../../src/bashlib/str.sh
. ../libs/test_utils.sh

test_case1 ()
{
    local demo_str='*1*a*b'
    local str_count=${|str_count "$demo_str" '*';}
    if [[ "$str_count" == '3' ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    local demo_str="我是中文hahah中文文"
    local str_count=${|str_count "$demo_str" '中文';}
    if [[ "$str_count" == '2' ]] ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

    local demo_str="我是中文hahah中文文"
    local str_count=${|str_count "$demo_str" '中x文';}
    if [[ "$str_count" == '0' ]] ; then
        log_test 1 3
    else
        log_test 0 3 ; return 1
    fi

    local demo_str=""
    local str_count=${|str_count "$demo_str" '中x文';}
    if [[ "$str_count" == '-1' ]] ; then
        log_test 1 4
    else
        log_test 0 4 ; return 1
    fi

    return 0
}

test_case2 ()
{
    local str1=''
    local sep1=''
    local str2='xxyykkyy23'
    local sep2="904"
    local sep3='yy'
    local str3='xxyy'
    
    local -a "arr1=(${|str_split "$str1" "$sep1";})"
    local -a "arr2=(${|str_split "$str1" "$sep2";})"
    local -a "arr3=(${|str_split "$str2" "$sep1";})"
    local -a "arr4=(${|str_split "$str2" "$sep2";})"
    local -a "arr5=(${|str_split "$str2" "$sep3";})"
    local -a "arr6=(${|str_split "$str3" "$sep1";})"
    local -a "arr7=(${|str_split "$str3" "$sep2";})"
    local -a "arr8=(${|str_split "$str3" "$sep3";})"

    # declare -p arr1 arr2 arr3 arr4 arr5 arr6 arr7 arr8
    
    local -a arr1_s=()
    local -a arr2_s=()
    local -a arr3_s=([0]="x" [1]="x" [2]="y" [3]="y" [4]="k" [5]="k" [6]="y" [7]="y" [8]="2" [9]="3")
    local -a arr4_s=([0]="xxyykkyy23")
    local -a arr5_s=([0]="xx" [1]="kk" [2]="23")
    local -a arr6_s=([0]="x" [1]="x" [2]="y" [3]="y")
    local -a arr7_s=([0]="xxyy")
    local -a arr8_s=([0]="xx")

    if  assert_array a arr1 arr1_s &&
        assert_array a arr2 arr2_s &&
        assert_array a arr3 arr3_s &&
        assert_array a arr4 arr4_s &&
        assert_array a arr5 arr5_s &&
        assert_array a arr6 arr6_s &&
        assert_array a arr7 arr7_s &&
        assert_array a arr8 arr8_s ; then
        log_test 1 4
    else
        log_test 0 4 ; return 1
    fi

    return 0
}

eval -- "${|AS_RUN_TEST_CASES;}"


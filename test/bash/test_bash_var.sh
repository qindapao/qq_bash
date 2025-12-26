#!/usr/bin/env bash

. ../libs/test_utils.sh

# ${@@Q} This is legal and means that all positional parameters are quoted.
test_case1 ()
{
    test_case1_inner ()
    {
        local -a get_arr=("${@@Q}")
        local var1="a 1"
        local var2="b 2"
        local var3="c 3"
        local var4="d 4"

        if ((4==${#get_arr[@]})) &&
            [[ "${get_arr[0]}" == "${var1@Q}" ]] &&
            [[ "${get_arr[1]}" == "${var2@Q}" ]] &&
            [[ "${get_arr[2]}" == "${var3@Q}" ]] &&
            [[ "${get_arr[3]}" == "${var4@Q}" ]] ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi

    }
    test_case1_inner "a 1" "b 2" "c 3" "d 4" || return $?
}

# How to pass an associative array to a function as a parameter
test_case2 ()
{
    local get_dict=4
    test_case2_inner ()
    {
        local -A "get_dict=(${*@Q})"
        local var1="a 1"
        local var2="b 2"
        local var3="c 3"
        local var4="d 4"

        local -A expect_dict=(['a 1']='b 2' ['c 3']='d 4')

        if assert_array 'A' get_dict expect_dict ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi

    }

    # Pass parameters in the order of key-value pairs
    test_case2_inner "a 1" "b 2" "c 3" "d 4" || return $?
    
    if [[ "$get_dict" == 4 ]] ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi
}

# $# and indirect access ! Reverse command parameters
test_case3 ()
{
    # Put the first parameter back to the end
    test_case3_inner ()
    {
        set -- "${@:2}" "$1"
        if [[ "$1" == '2 b' ]] &&
            [[ "$2" == '3 c' ]] &&
            [[ "$3" == '4 d' ]] &&
            [[ "$4" == '1 a' ]] ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi
    }
    
    test_case3_inner "1 a" "2 b" "3 c" "4 d" || return $?

    test_case3_inner2 ()
    {
        set -- "${@:2}" "$1"
        local -a get_arr=()
        while (($#>1)) ; do
            get_arr+=("${!#}" "$1" "$2")
            shift 2
        done
        local -a expect_arr=(
            'name head' '1 a' '2 b'
            'name head' '3 c' '4 d'
            'name head' '5 e' '6 f')

        if assert_array 'a' get_arr expect_arr ; then
            log_test 1 2
        else
            log_test 0 2 ; return 1
        fi
    }

    test_case3_inner2 "name head" "1 a" "2 b" "3 c" "4 d" "5 e" "6 f" || return $?
    return 0
}

# Positional parameters exceeding 9 must use braces
# Otherwise it will be split into $[0-9] + the following number
test_case4 ()
{
    test_case4_inner ()
    {
        local a=$1
        local b=$2
        local c=$9
        # "$1" + "0"
        local d=$10
        local e=${10}
        local f=${11}
        local g=${12}
        # "$1" + "2"
        local h=$12

        if [[ "$a" == 'a' ]] &&
            [[ "$b" ==  'b' ]] &&
            [[ "$c" ==  'i' ]] &&
            [[ "$d" ==  'a0' ]] &&
            [[ "$e" ==  'j' ]] &&
            [[ "$f" ==  'k' ]] &&
            [[ "$g" ==  'l' ]] &&
            [[ "$h" ==  'a2' ]] ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi
    }
    
    test_case4_inner a b c d e f g h i j k l || return $?
    return 0
}

eval -- "${|AS_RUN_TEST_CASES;}"


#!/usr/bin/env bash

. ../libs/test_utils.sh

# Double quote assignment of array, splitting string into words
# If there is no local keyword, directly "my_arr=($1)" will not work and will
# not be treated as a command.
test_case1 ()
{
    test_case1_inner ()
    {
        local -a "my_arr=($1)"
        local -a my_arr_expect1=(a b c d)
        if assert_array 'a' my_arr my_arr_expect1 ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi
        return 0
    }
    
    local -a my_arr=(1 2 3 4)
    local -a my_arr_expect2=(1 2 3 4)
    test_case1_inner '"a" "b" "c" "d"' || return $?
    unset -f test_case1_inner

    if assert_array 'a' my_arr my_arr_expect2 ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

}

# Double quoted assignment of associative array, string split into words
test_case2 ()
{
    test_case2_inner ()
    {
        local -A "my_dict=($1)"
        local -A my_dict_expect1=([a]=1 [b]=1 [c]=1 [d]=1)
        if assert_array 'A' my_dict my_dict_expect1 ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi
        return 0
    }
    
    local -A my_dict=([1]=1 [2]=1 [3]=1 [4]=1)
    local -A my_dict_expect2=([1]=1 [2]=1 [3]=1 [4]=1)
    test_case2_inner '"a" 1 "b" 1 "c" 1 "d" 1' || return $?
    unset -f test_case2_inner

    if assert_array 'A' my_dict my_dict_expect2 ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

}

# Double quoted assignment of associative array, string split into words
test_case3 ()
{
    test_case3_inner ()
    {
        local -A my_dict
        # There is no local command in this case, eval must be used
        eval -- "my_dict=($1)"
        local -A my_dict_expect1=([a]=1 [b]=1 [c]=1 [d]=1)
        if assert_array 'A' my_dict my_dict_expect1 ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi
        return 0
    }
    
    local -A my_dict=([1]=1 [2]=1 [3]=1 [4]=1)
    local -A my_dict_expect2=([1]=1 [2]=1 [3]=1 [4]=1)
    test_case3_inner '"a" 1 "b" 1 "c" 1 "d" 1' || return $?
    unset -f test_case3_inner

    if assert_array 'A' my_dict my_dict_expect2 ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

}

# Assign multiple variables at once
# But it is not recommended to write like this because it is inconvenient to debug!
# {i,j,k}=3 This is not possible, you must add local or declare
test_case4 ()
{
    local {i,j,k}=3
    local pre_{i,j,k}=4
    if [[ "$i" == 3 ]] &&
        [[ "$j" == 3 ]] &&
        [[ "$k" == 3 ]] &&
        [[ "$pre_i" == 4 ]] &&
        [[ "$pre_j" == 4 ]] &&
        [[ "$pre_k" == 4 ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
}

eval -- "${|AS_RUN_TEST_CASES;}"




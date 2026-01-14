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

test_case5 ()
{
    echo "test_case5 ret----------"
    local a=1 b=2
    local -n c=a d=b
    local all_var_info=$(local)
    local all_var_spec=$'declare -- a="1"\ndeclare -- b="2"\ndeclare -n c="a"\ndeclare -n d="b"'
    if [[ "$all_var_info" == "$all_var_spec" ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

test_case6 ()
{
    echo "test_case6 ret----------"
    local a=1 b=2
    local -n c=a d=b
    # The reason why the local command here does not print anything is that the
    # syntax of ${ cmd;} and ${|cmd;} is equivalent to creating an anonymous
    # function to execute the command. Since the current local command here
    # does not print for the new function.
    local all_var_info=${ local;}
    if [[ -z "$all_var_info" ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

test_case7 ()
{
    test_case7_inner ()
    {
        local IFS=$'\n'
        if [[ "$IFS" = $'\n' ]] ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi

        return 0
    }

    local old_ifs=$IFS
    test_case7_inner
    test_case7_inner

    if [[ "$IFS" = "$old_ifs" ]] ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi
    
    return 0
}

# localvar_inherit
# 让内层函数作用域的变量继承外层作用域的属性和值
# 内层函数不要污染外层函数的变量
# 但又希望它能安全地“遮蔽”外层变量而不破坏类型
# 但是一般情况下这个选项对普通用户的意义不大
# 不要轻易打开，会发生更多的未知行为
test_case8 ()
{
    local localvar_inherit_on=0

    shopt -q localvar_inherit &>/dev/null || {
        shopt -s localvar_inherit
        localvar_inherit_on=1
    }

    test_case8_outer ()
    {
        local -a arr=(1 2 3)
        test_case8_inner
        local arr_spec=(1 2 3)

        if assert_array a arr arr_spec ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi
    }

    test_case8_inner ()
    {
        local arr
        arr[0]=5
        local arr_spec=(5 2 3)
        if assert_array a arr arr_spec ; then
            log_test 1 1
        else
            log_test 0 1 ; return 1
        fi

        return 0
    }
    
    test_case8_outer

    ((localvar_inherit_on)) && shopt -u localvar_inherit
}

# localvar_unset 
# 这个选项开启后的作用是
# test_case_inner3 这里下层函数调用 unset 并不会在 test_case_inner3 里面
# 马上移除这个 var, 所以 var=value3 并不会影响到 test_case_inner2
#
# 如果不开这个选项，那么 test_case_inner3 中的 var 被直接移除
# test_case_inne2 中的 var 被赋值为 value3
test_case9 ()
{
    local localvar_unset_on=0

    shopt -q localvar_unset &>/dev/null || {
        shopt -s localvar_unset
        localvar_unset_on=1
    }

    test_case9_unset() { unset "$@" ; }

    test_case_inner1 ()
    {
        local var=value1
        test_case_inner2 var
        var_print+="$var"
    }

    test_case_inner2 ()
    {
        local var=value2
        test_case_inner3 var
        var_print+="$var"
    }
    
    test_case_inner3 ()
    {
        local var
        test_case9_unset "$@"
        var=value3
    }

    local var_print=
    local var=valueout
    test_case_inner1
    var_print+="$var"

    ((localvar_unset_on)) && shopt -u localvar_unset

    if [[ "$var_print" == "value2value1valueout" ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    return 0
}

# step_test 9

eval -- "${|AS_RUN_TEST_CASES;}"


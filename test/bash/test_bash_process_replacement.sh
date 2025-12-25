#!/usr/bin/env bash

. ../libs/test_utils.sh

# ${|function;} The behavior is safe. Except for the REPLY variable,
# other variables in the upper scope can be modified.
test_case1 ()
{
    REPLY=a
    local xx=''
    local other_var=4
    test_case1_inner ()
    {
        local xx=4
        other_var=x
        REPLY=$xx
    }
    local get_reply=${|test_case1_inner;}
    if [[ "$get_reply" == 4 ]] &&
        [[ "$REPLY" == a ]] &&
        [[ "$other_var" == x ]] &&
        [[ -z "$xx" ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

}

# ${|function;} Same situation without direct capture
test_case2 ()
{
    REPLY=a
    local xx=""
    local other_var=4
    test_case2_inner ()
    {
        local xx=4
        other_var=x
        REPLY="$xx u y i"
    }

    local loop
    local -a loop_arr=()
    for loop in ${|test_case2_inner;} ; do
        loop_arr+=("$loop")
    done
    local -a expect_arr=(4 u y i)

    if  assert_array 'a' loop_arr expect_arr &&
        [[ "$other_var" == x ]] &&
        [[ -z "$xx" ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi
}

eval -- "$AS_RUN_TEST_CASES"




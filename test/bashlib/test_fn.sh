#!/usr/bin/env bash

. ../../src/bashlib/fn.sh
. ../libs/test_utils.sh

# test fn_map_inplace
test_case1 ()
{
    test_case1_inner1 ()
    {
        REPLY=$(($1+1))
    }

    local -a arr_xx=(1 2 3 4 5)
    local -a arr_xx_spec=(2 3 4 5 6)
    fn_map_inplace "${arr_xx[@]@k}" arr_xx test_case1_inner1

    if assert_array 'a' arr_xx arr_xx_spec ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    test_case1_inner2 ()
    {
        REPLY="${1}append str"
    }

    local -A "dict_xx=(${AS_DICT_TEMP[@]@K})"
    fn_map_inplace "${dict_xx[@]@k}" dict_xx test_case1_inner2 

    declare -A dict_xx_spec=(
        ["(xx:yy)"]="6append str"
        ["]"]="strangeappend str"
        ["xxx->xxx->xxx->xx:xx.x-/dev/fd/61-/dev/fd/60"]="1append str"
        [$'zy \ngeg \n']=$' gge geg(xx)[ggel\n\n]ggeegappend str'
        ["xxx xxx->xxx->xxx->xx:xx.x-/dev/fd/61-/dev/fd/60"]="1append str"
        ["xxx xxx->xxx->xxx->xx:xx.x->(xxx:xx)->(xxxxx:xxxx)"]="2append str" )

    if assert_array 'A' dict_xx dict_xx_spec ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

    return 0
}

eval -- "${|AS_RUN_TEST_CASES;}"


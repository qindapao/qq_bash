#!/usr/bin/env bash

. ../libs/test_utils.sh

# 在新版本的bash中下面三种格式都正确
# unset -v 'k["${tmp_key[cnt]}"]'    (某些bash版本可能发生扩展)
# unset -v 'k[${tmp_key[cnt]}]'      (某些bash版本可能发生扩展)
# tmp_key="${tmp_key[cnt]}" ; unset -v 'k["$tmp_key"]'   (推荐)
test_case1 ()
{
    local -A k_temp=(
        ["(xx:yy)"]="6" ["xxx->xxx->xxx->xx:xx.x-/dev/fd/61-/dev/fd/60"]="1"
        ["xxx xxx->xxx->xxx->xx:xx.x-/dev/fd/61-/dev/fd/60"]="1"
        ["xxx xxx->xxx->xxx->xx:xx.x->(xxx:xx)->(xxxxx:xxxx)"]="2" )

    local -A k1=(
        ["(xx:yy)"]="6" ["xxx->xxx->xxx->xx:xx.x-/dev/fd/61-/dev/fd/60"]="1"
        ["xxx xxx->xxx->xxx->xx:xx.x-/dev/fd/61-/dev/fd/60"]="1")

    local cnt=0

    eval -- local -A k=(${k_temp[*]@K})
    local -A "k=(${k_temp[*]@K})"
    declare -p k

    tmp_key=("xxx xxx->xxx->xxx->xx:xx.x->(xxx:xx)->(xxxxx:xxxx)")
    if [[ -v 'k[${tmp_key[cnt]}]' ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    if [[ -v 'k["${tmp_key[cnt]}"]' ]] ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

    unset -v 'k["${tmp_key[cnt]}"]'
    unset -v 'k[${tmp_key[cnt]}]'

    tmp_key="${tmp_key[cnt]}"

    unset -v 'k["$tmp_key"]'

    return
}

eval -- "${|AS_RUN_TEST_CASES;}"



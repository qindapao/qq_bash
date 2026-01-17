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

    eval -- local -A k=(${k_temp[*]@K})
    local -A "k=(${k_temp[*]@K})"
    unset -v 'k["${tmp_key[cnt]}"]'
    if [[ -v 'k[${tmp_key[cnt]}]' ]] ; then
        log_test 0 3 ; return 1
    else
        log_test 1 3
    fi
    

    eval -- local -A k=(${k_temp[*]@K})
    local -A "k=(${k_temp[*]@K})"
    unset -v 'k[${tmp_key[cnt]}]'
    if [[ -v 'k[${tmp_key[cnt]}]' ]] ; then
        log_test 0 4 ; return 1
    else
        log_test 1 4
    fi

    eval -- local -A k=(${k_temp[*]@K})
    local -A "k=(${k_temp[*]@K})"
    tmp_key="${tmp_key[cnt]}"
    unset -v 'k["$tmp_key"]'
    if [[ -v 'k[${tmp_key[cnt]}]' ]] ; then
        log_test 0 5 ; return 1
    else
        log_test 1 5
    fi

    eval -- local -A k=(${k_temp[*]@K})
    local -A "k=(${k_temp[*]@K})"
    tmp_key="${tmp_key[cnt]}"
    unset -v 'k[$tmp_key]'
    if [[ -v 'k[${tmp_key[cnt]}]' ]] ; then
        log_test 0 6 ; return 1
    else
        log_test 1 6
    fi

    return
}

# unset complex keys of associative arrays
test_case2 ()
{
    local -A assoc
    local var='gge
geg()
xxx xxx->xxx->xxx->xx:xx.x->(xxx:xx)->(xxxxx:xxxx)
'
    assoc[$var]=1
    local -A assoc_spec1=([$'gge\ngeg()\nxxx xxx->xxx->xxx->xx:xx.x->(xxx:xx)->(xxxxx:xxxx)\n']="1" )
    local -A assoc_spec2=()
    if assert_array 'A' assoc assoc_spec1 ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    if [[ -v 'assoc[$var]' ]] ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

    unset -v 'assoc[$var]'
    if assert_array 'A' assoc assoc_spec2 ; then
        log_test 1 3
    else
        log_test 0 3 ; return 1
    fi
    return 0
}

test_case3 ()
{
    local k1='*'
    local k2='@'
    local -A assoc=(['*']=1 ['@']=2)

    unset -v 'assoc[$k1]'

    if [[ -v 'assoc[$k2]' ]] ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    if [[ -v 'assoc["$k1"]' ]] ; then
        log_test 0 2 ; return 1
    else
        log_test 1 2
    fi

    local -A assoc=(['*']=1 ['@']=2)
    unset -v 'assoc[$k2]'

    if [[ -v 'assoc[$k1]' ]] ; then
        log_test 1 3
    else
        log_test 0 3 ; return 1
    fi

    if [[ -v 'assoc["$k2"]' ]] ; then
        log_test 0 4 ; return 1
    else
        log_test 1 4
    fi

    local -A assoc=(['*']=1 ['@']=2)
    # 现在这样也没问题了
    unset -v assoc[@]

    if [[ -v 'assoc["$k1"]' && ! -v 'assoc["$k2"]' ]] ; then
        log_test 1 5
    else
        log_test 0 5 ; return 1
    fi

    local -A assoc=(['*']=1 ['@']=2)
    # 现在这样也没问题了
    unset -v assoc[*]

    if [[ ! -v 'assoc["$k1"]' && -v 'assoc["$k2"]' ]] ; then
        log_test 1 6
    else
        log_test 0 6 ; return 1
    fi

    return 0
}

eval -- "${|AS_RUN_TEST_CASES;}"



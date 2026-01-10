#!/usr/bin/env bash

. ../../src/bashlib/array.sh
. ../libs/test_utils.sh

test_case1 ()
{
    local arr=()
    local -i i
    for ((i=0; i<150; i++)); do
        local tmp=$((RANDOM % 10000))
        arr[i++]=$tmp
        arr[i++]=$tmp
        arr[i]=$tmp
    done

    local arr1=("${arr[@]}")

    array_qsort arr1 '-gt'
    arr2=($(printf "%s\n" "${arr[@]}" | sort -n))

    if [[ "${arr1[*]}" == "${arr2[*]}" ]] ; then
        echo "${FUNCNAME[0]} test pass."
    else
        echo "${FUNCNAME[0]} test fail."
        return 1
    fi

    local arr=()
    for ((i=0; i<2000; i++)); do
        arr[i]=$((RANDOM % 10000))
    done
    arr[2000]="x  y  z"
    arr[2001]='1  2  3'
    local arr1=("${arr[@]}")

    array_qsort arr1 '-gt'
    arr2=($(printf "%s\n" "${arr[@]}" | sort -n))

    if [[ "${arr1[*]}" == "${arr2[*]}" ]] ; then
        echo "${FUNCNAME[0]} test pass."
    else
        echo "${FUNCNAME[0]} test fail."
        return 1
    fi

    return 0
}

test_case2 ()
{
    local arr=()
    local -i i
    for ((i=0; i<150; i++)); do
        local tmp=$((RANDOM % 10000))
        arr[i++]=$tmp
        arr[i++]=$tmp
        arr[i]=$tmp
    done

    local arr1=("${arr[@]}")

    array_qsort arr1 '-lt'
    arr2=($(printf "%s\n" "${arr[@]}" | sort -rn))

    if [[ "${arr1[*]}" == "${arr2[*]}" ]] ; then
        echo "${FUNCNAME[0]} test pass."
    else
        echo "${FUNCNAME[0]} test fail."
        return 1
    fi

    local arr=()
    for ((i=0; i<2000; i++)); do
        arr[i]=$((RANDOM % 10000))
    done
    arr[2000]="x  y  z"
    arr[2001]='1  2  3'
    local arr1=("${arr[@]}")

    array_qsort arr1 '-lt'
    arr2=($(printf "%s\n" "${arr[@]}" | sort -rn))

    if [[ "${arr1[*]}" == "${arr2[*]}" ]] ; then
        echo "${FUNCNAME[0]} test pass."
    else
        echo "${FUNCNAME[0]} test fail."
        return 1
    fi

    return 0
}

test_case3 ()
{
    local arr=()
    local -i i
    for ((i=0; i<150; i++)); do
        local tmp=$((RANDOM % 10000))
        arr[i++]=$tmp
        arr[i++]=$tmp
        arr[i]=$tmp
    done

    local arr1=("${arr[@]}")

    array_qsort arr1 '>'
    arr2=($(printf "%s\n" "${arr[@]}" | sort))

    if [[ "${arr1[*]}" == "${arr2[*]}" ]] ; then
        echo "${FUNCNAME[0]} test pass."
    else
        echo "${FUNCNAME[0]} test fail."
        return 1
    fi

    local arr=()
    for ((i=0; i<2000; i++)); do
        arr[i]=$((RANDOM % 10000))
    done
    arr[2000]="x  y  z"
    arr[2001]='1  2  3'
    local arr1=("${arr[@]}")

    array_qsort arr1 '>'
    arr2=($(printf "%s\n" "${arr[@]}" | sort))

    if [[ "${arr1[*]}" == "${arr2[*]}" ]] ; then
        echo "${FUNCNAME[0]} test pass."
    else
        echo "${FUNCNAME[0]} test fail."
        return 1
    fi

    return 0
}

test_case4 ()
{
    local arr=()
    local -i i
    for ((i=0; i<150; i++)); do
        local tmp=$((RANDOM % 10000))
        arr[i++]=$tmp
        arr[i++]=$tmp
        arr[i]=$tmp
    done

    local arr1=("${arr[@]}")

    array_qsort arr1 '<'
    arr2=($(printf "%s\n" "${arr[@]}" | sort -r))

    if [[ "${arr1[*]}" == "${arr2[*]}" ]] ; then
        echo "${FUNCNAME[0]} test pass."
    else
        echo "${FUNCNAME[0]} test fail."
        return 1
    fi

    local arr=()
    for ((i=0; i<2000; i++)); do
        arr[i]=$((RANDOM % 10000))
    done
    arr[2000]="x  y  z"
    arr[2001]='1  2  3'
    local arr1=("${arr[@]}")

    array_qsort arr1 '<'
    arr2=($(printf "%s\n" "${arr[@]}" | sort -r))

    if [[ "${arr1[*]}" == "${arr2[*]}" ]] ; then
        echo "${FUNCNAME[0]} test pass."
    else
        echo "${FUNCNAME[0]} test fail."
        return 1
    fi

    return 0
}

test_case5 ()
{
    local arr=(1 2 3 4 6)
    local value=5
    array_sorted_insert arr "$value" '-gt'
    if [[ "${arr[*]}" == "1 2 3 4 5 6" ]] ; then
        echo "${FUNCNAME[0]} test pass."
    else
        echo "${FUNCNAME[0]} test fail."
        return 1
    fi
    return 0
}

test_case6 ()
{
    local arr=(10 9 7 6 5 4 2 1)
    local value=2
    array_sorted_insert arr "$value" '-lt'
    if [[ "${arr[*]}" == "10 9 7 6 5 4 2 2 1" ]] ; then
        echo "${FUNCNAME[0]} test pass."
    else
        echo "${FUNCNAME[0]} test fail."
        return 1
    fi
    return 0
}

test_case7 ()
{
    local arr=(a b c f g)
    local value=e
    array_sorted_insert arr "$value" '>'
    if [[ "${arr[*]}" == "a b c e f g" ]] ; then
        echo "${FUNCNAME[0]} test pass."
    else
        echo "${FUNCNAME[0]} test fail."
        return 1
    fi
    return 0
}

test_case8 ()
{
    local arr=(g f b a)
    local value=d
    array_sorted_insert arr "$value" '<'
    if [[ "${arr[*]}" == "g f d b a" ]] ; then
        echo "${FUNCNAME[0]} test pass."
    else
        echo "${FUNCNAME[0]} test fail."
        return 1
    fi
    return 0
}

test_case10 ()
{
    local x=(1 2 3 4)
    local y=(1 2 3 4 5 6)
    
    if array_is_subset x y ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    local x=(1 3 4)
    local y=(1 2 3 4 5 6)
    
    if array_is_subset x y ; then
        log_test 0 2 ; return 1
    else
        log_test 1 2
    fi

    local -A x_map=(['a 1']=" 1 2" ['a 2']="3 4")
    local -A y_map=(['a 1']=" 1 2" ['a 2']="3 4" [ohter]=3)

    if array_is_subset x_map y_map ; then
        log_test 1 3
    else
        log_test 0 3 ; return 1
    fi
    

    return 0

}

test_case11 ()
{
    local -
    # set -x
    local a=(1 2 "a 3" 4 5 "a 3" 6)
    local e="a 3"
    array_delete_first_e a "$e"
    local a_spec=(
    1 2 
    [3]=4
    5 "a 3" 6)

    if assert_array a a a_spec ; then
        log_test 1 1
    else
        log_test 0 1 ; return 1
    fi

    local a=(1 2 "a 3" 4 5 "a 3" 6)
    array_delete_e a "$e"
    local a_spec=(
    1 2 
    [3]=4
    5
    [6]=6)

    if assert_array a a a_spec ; then
        log_test 1 2
    else
        log_test 0 2 ; return 1
    fi

    return 0
}


# step_test 11

eval -- "${|AS_RUN_TEST_CASES;}"


#!/usr/bin/env bash

. array.sh


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

test_case1 &&
test_case2 &&
test_case3 &&
test_case4 &&
test_case5 &&
test_case6 &&
test_case7 &&
test_case8


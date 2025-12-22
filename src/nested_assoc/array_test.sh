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

    array_sort arr1 '-gt'
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

    array_sort arr1 '-gt'
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

    array_sort arr1 '-lt'
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

    array_sort arr1 '-lt'
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

    array_sort arr1 '>'
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

    array_sort arr1 '>'
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

    array_sort arr1 '<'
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

    array_sort arr1 '<'
    arr2=($(printf "%s\n" "${arr[@]}" | sort -r))

    if [[ "${arr1[*]}" == "${arr2[*]}" ]] ; then
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
test_case4


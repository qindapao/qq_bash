#!/usr/bin/env bash

date_log ()
{
    printf '%(%Y_%m_%d_%H_%M_%S)T' -1
}

date_print ()
{
    printf '%(%Y-%m-%d %H:%M:%S)T' -1
}

exec_all_test_case ()
{
    local start_time=${ date_print;}

    local test_report="${PWD}/test_report_${ date_log;}.txt"
    local -a test_case_files=() 

    local is_globstar_set=0 is_nullglob_set=0 is_dotglob_unset=0

    shopt -q globstar || { shopt -s globstar ; is_globstar_set=1 ; }
    shopt -q nullglob || { shopt -s nullglob ; is_nullglob_set=1 ; }
    shopt -q dotglob  && { shopt -u dotglob  ; is_dotglob_unset=1 ; }

    cd "test/"
    local -a all_files=()
    local file_name
    for file_name in ** ; do
        [[ "$file_name" == *'/'test_*'.sh' ]] &&
        [[ "$file_name" != *'/test_utils.sh' ]] &&
        [[ "$file_name" == *'.sh' ]] && {
            all_files+=("${file_name}")
        }
    done

    ((is_globstar_set)) && shopt -u globstar
    ((is_nullglob_set)) && shopt -u nullglob
    ((is_dotglob_unset)) && shopt -s dotglob

    local cur_dir=$PWD
    local is_test_fail=0 state
    for file_name in "${all_files[@]}" ; do
        cd ${file_name%/*}
        bash ${file_name##*/} > >(tee -a "$test_report")
        if (($?)) ; then
            echo "~~~~~~~~${file_name}~~~~~~~~ test fail!" | tee -a "$test_report"
            is_test_fail=1
        else
            echo "~~~~~~~~${file_name}~~~~~~~~ test pass!" | tee -a "$test_report"
        fi
        cd "$cur_dir"
    done
    
    local end_time=${ date_print;}
    local result=pass
    ((is_test_fail)) && result=fail
    echo "test start in ${start_time},end_in ${end_time},result:${result}."
    return $is_test_fail
}

exec_all_test_case


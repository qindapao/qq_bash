#!/usr/bin/env bash

. ./src/bashlib/grammar.sh

date_log () { printf '%(%Y_%m_%d_%H_%M_%S)T' -1 ; }

date_print () { printf '%(%Y-%m-%d %H:%M:%S)T' -1 ; }

dir_is_not_exclude ()
{
    local path_str=$1 dir_i
    for dir_i in "${EXCLUDE_DIRS[@]}" ; do
        [[ "$path_str" == "${dir_i}/"* ]] && return 1
    done
    return 0
}

exec_all_test_case ()
{
    local start_time=$(date_print)

    local test_report="${PWD}/test_report_$(date_log).txt"
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
        [[ "$file_name" != *'libs/'*'.sh' ]] &&
        [[ "$file_name" == *'.sh' ]] &&
        dir_is_not_exclude "$file_name" && {
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
        "$BASH_BIN" ${file_name##*/} > >(tee -a "$test_report")
        if (($?)) ; then
            echo "~~~~~~~~${file_name}~~~~~~~~ test fail!" | tee -a "$test_report"
            is_test_fail=1
        else
            echo "~~~~~~~~${file_name}~~~~~~~~ test pass!" | tee -a "$test_report"
        fi
        cd "$cur_dir"
    done
    
    local end_time=$(date_print)
    local result=pass
    ((is_test_fail)) && result=fail
    echo "test start in ${start_time},end_in ${end_time},result:${result}."
    return $is_test_fail
}

print_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

A lightweight Bash test runner that executes all test_*.sh files under ./test/,
with support for custom interpreters, directory exclusion, and more.

Options:
  -b, --bash <path>        Specify the Bash interpreter to run test cases.
                           Default: "bash"
                           Example: -b /home/admin/bash

  -v, --exclude <dir>      Exclude a directory (relative to ./test/) from testing.
                           Can be specified multiple times.
                           Example: -v libs/ -v old/

  -h, --help               Show this help message and exit.

Examples:
  Run tests with system bash:
      $0

  Run tests with a specific bash version:
      $0 -b /home/admin/bash

  Exclude multiple directories:
      $0 -v libs/ -v bash/

  Combine options:
      $0 -b /home/admin/bash -v bash/ -v old/

EOF
}

PARSED=$(getopt \
    --options b:v:h \
    --long bash:,exclude:,help: \
    --name "$0" \
    -- "$@") || exit 1

eval set -- "$PARSED"

EXCLUDE_DIRS=()

for ((;;)) ; do
    case "$1" in
        -b|--bash)      BASH_BIN="$2" ; shift 2 ;;
        -v|--exclude)   EXCLUDE_DIRS+=("${2%"/"}") ; shift 2 ;;
        -h|--help)      print_help ; exit 0 ;;
        --) shift ; break ;;
        *)  echo "Unknown option: $1" ; exit 1 ;;
    esac
done
BASH_BIN=${BASH_BIN:-"bash"}

exec_all_test_case


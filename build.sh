#!/usr/bin/env bash

. ./src/bashlib/grammar.sh

FILES_TO_BE_PROCESSED=(
    "./src/bashlib/var.in"
    "./src/bashlib/str.in"
    "./src/bashlib/float.in"
    "./src/bashlib/array.in"
    "./src/bashlib/x.in"
    "./src/bashlib/data.in"
    "./src/bashlib/xo.in"
    "./test/bashlib/test_x.in"
)

clear_build_dir ()
{
    local f
    for f in "${FILES_TO_BE_PROCESSED[@]}" ; do
        rm -f "${f%".in"}.sh"
    done
}

process_file() {
    local f f_line trimmed
    local in_block=1
    local expr var_name value op

    for f in "${FILES_TO_BE_PROCESSED[@]}"; do
        while IFS= read -r f_line; do
            trimmed="${f_line#"${f_line%%[![:space:]]*}"}"

            case "$trimmed" in
            '#@if '*)
                expr=${trimmed#"#@if "}

                # Convert expression to bash executable form
                # For example: current_shell_process_replace==1
                # become:      ((BASH_GRAMMAR[current_shell_process_replace]==1))
                var_name=${expr%%[^a-z0-9A-Z_]*}
                value=${expr##*[^a-z0-9A-Z_]}
                op=${expr#"$var_name"}
                op=${op%"$value"}

                if eval -- "((BASH_GRAMMAR[$var_name]${op}${value}))" ; then
                    in_block=1
                else
                    in_block=0
                fi
                continue
                ;;
            "#@endif")
                in_block=1
                continue
                ;;
            esac

            (( in_block )) && printf '%s\n' "$f_line" >> "${f%".in"}.sh"
        done < "$f"
    done
}

[[ "$1" == '-d' ]] && { clear_build_dir ; exit 0 ; }

clear_build_dir
process_file

# 语法检查：生成的文件语法错时立刻报错并指出文件。
# 直接跑游戏时，这类错误常常只表现为“某个函数 command not found”，很难查。
_check_syntax ()
{
    local f rc=0
    for f in "${FILES_TO_BE_PROCESSED[@]}" ; do
        f=${f%".in"}.sh
        bash -n "$f" || { echo "SYNTAX ERROR: $f" >&2 ; rc=1 ; }
    done
    return "$rc"
}

_check_syntax



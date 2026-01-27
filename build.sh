#!/usr/bin/env bash

. ./src/bashlib/grammar.sh

BUILD_DIR="./build"

FILES_TO_BE_PROCESSED=(
    "./src/bashlib/meta.sh"
    "./src/bashlib/var.sh"
    "./src/bashlib/fn.sh"
    "./src/bashlib/str.sh"
    "./src/bashlib/float.sh"
    "./src/bashlib/array.sh"
    "./src/bashlib/trie.sh"
    "./src/bashlib/my_class.sh"
    "./src/bashlib/mid_class.sh"
    "./src/bashlib/base_class.sh"
)

clear_build_dir ()
{
    local f
    for f in "${FILES_TO_BE_PROCESSED[@]}" ; do
        rm -f "${BUILD_DIR}/${f##*/}"
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

            (( in_block )) && printf '%s\n' "$f_line" >> "${BUILD_DIR}/${f##*/}"
        done < "$f"
    done
}

clear_build_dir
process_file



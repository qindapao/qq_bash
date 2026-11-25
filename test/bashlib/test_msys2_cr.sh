#!/usr/bin/env bash
#
# MSYS2/Git Bash regression test: CR survives the declaration-then-assign
# workaround, and value paths preserve CR (keys are not guaranteed).
#
# On Linux/macOS/other normal Bash platforms this test is a silent no-op:
# the platform does not have the MSYS2 CR stripping bug.

is_msys2=0
case "${OSTYPE:-}" in
    msys*|cygwin*) is_msys2=1 ;;
esac
case "$(uname -s 2>/dev/null || true)" in
    MSYS*|MINGW*|CYGWIN*) is_msys2=1 ;;
esac
(( is_msys2 )) || exit 0

. ../../src/bashlib/x.sh
. ../../src/bashlib/xe.sh

cr=$'\r'
FAILS=0
check_equal () {
    local label=$1 want=$2 got=$3
    if [[ "$want" == "$got" ]] ; then
        printf '  ok   %-42s\n' "$label"
    else
        printf '  FAIL %-42s want=%q got=%q\n' "$label" "$want" "$got"
        FAILS=$((FAILS + 1))
    fi
}

COPY_REPLY=
copy_compound () { local -a a=("$@") ; COPY_REPLY=${a[0]} ; }
copy_separate () { local -a a ; a=("$@") ; COPY_REPLY=${a[0]} ; }

# 已知 MSYS2 行为：声明时的复合赋值会吞 CR。这里只记录，不把它当断言，
# 以免未来 MSYS2 修好后用例反过来失败。
copy_compound "v${cr}"
if [[ "$COPY_REPLY" == "v${cr}" ]] ; then
    printf '  note MSYS2 CR bug not reproduced (platform may be fixed)\n'
else
    printf '  note MSYS2 CR bug reproduced by local -a a=("$@")\n'
fi

copy_separate "v${cr}"
check_equal 'declare-then-assign keeps CR' "v${cr}" "$COPY_REPLY"

declare -gA T=()
x_init T "$X_TYPE_OBJ"
declare -a w_test_msys2_cr__qinfo=()
x_qinserts T common:w_test_msys2_cr__qinfo '' "{k}$X" "v${cr}" || {
    echo 'FAIL: x_qinserts'
    exit 1
}
x_get_leaf T "{k}$X"
check_equal 'x_qinserts keeps CR in value' "v${cr}" "$REPLY"

declare -gA W=()
x_init W "$X_TYPE_OBJ"
x_insert W "{a${cr}b}$X{c}$X" "v"
WALK_CR_PHYS=
walk_cr_probe () { WALK_CR_PHYS=$6 ; }
x_walk W "{a${cr}b}$X" walk_cr_probe
check_equal 'x_walk keeps CR in physical key' "{a${cr}b}$X{c}$X" "$WALK_CR_PHYS"

# Values are part of the supported contract; keys are not.
test_value_cr () {
    local val="v${cr}x"
    local path="{leaf}$X"
    local -A V=()
    x_init V "$X_TYPE_OBJ"
    x_insert V "$path" "$val"

    x_get_leaf V "$path"
    check_equal 'x_get_leaf keeps CR in value' "$val" "$REPLY"

    local -A VT=()
    x_get_tree VT V ''
    x_get_leaf VT "$path"
    check_equal 'x_get_tree keeps CR in value' "$val" "$REPLY"

    local -A VI=()
    x_id_rebuild V VI
    x_get_leaf VI "$path"
    check_equal 'x_id_rebuild keeps CR in value' "$val" "$REPLY"

    local dump
    dump=$(x_dump V '' 4 2)
    local -A VR=()
    x_rebuild_from_dump VR "$dump"
    x_get_leaf VR "$path"
    check_equal 'x_dump/x_rebuild keeps CR in value' "$val" "$REPLY"

    x_iter V '' $((2#11111))
    local line
    while IFS= read -r line ; do
        local -a "tuple=($line)"
        check_equal 'x_iter keeps CR in value' "$val" "${tuple[3]}"
    done <<< "$REPLY"

    local -A info=()
    _x_token_to_node_id info V "$path" 0 0 1
    check_equal '_x_token_to_node_id keeps CR in value' "$val" "${info[value]}"

    local -A flat=()
    x_layer_get_flat obj V '' flat
    check_equal 'x_layer_get_flat keeps CR in value' "$val" "${flat[leaf]}"

    local -A A=()
    x_init A "$X_TYPE_ARR"
    x_insert A "[0]$X" "$val"
    local -a aflat=()
    x_layer_get_flat arr A '' aflat
    check_equal 'array flat keeps CR in value' "$val" "${aflat[0]}"
}
test_value_cr

if command -v gobolt >/dev/null 2>&1 ; then
    . ../../src/bashlib/xj.sh
    test_json_value_cr () {
        local json='{"obj":"v\rx","arr":["w\ry"]}'
        local -A J=()
        x_from_json J "$json"
        x_get_leaf J "{obj}$X"
        check_equal 'x_from_json keeps CR in value' $'v\rx' "$REPLY"
        x_get_leaf J "{arr}$X[0]$X"
        check_equal 'x_from_json array keeps CR in value' $'w\ry' "$REPLY"

        x_to_json J
        local -A J2=()
        x_from_json J2 "$REPLY"
        x_get_leaf J2 "{obj}$X"
        check_equal 'x_to_json keeps CR in value' $'v\rx' "$REPLY"
    }
    test_json_value_cr
fi

if (( FAILS )) ; then
    printf '%d assertion(s) failed\n' "$FAILS"
    exit 1
fi
echo 'PASS: MSYS2 CR workaround'

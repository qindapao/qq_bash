#!/usr/bin/env bash
#
# MSYS2/Git Bash regression test: CR survives the declaration-then-assign
# workaround, and x_qinserts preserves CR in values.
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

if (( FAILS )) ; then
    printf '%d assertion(s) failed\n' "$FAILS"
    exit 1
fi
echo 'PASS: MSYS2 CR workaround'

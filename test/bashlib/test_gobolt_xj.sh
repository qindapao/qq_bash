#!/usr/bin/env bash

. ../libs/test_utils.sh
. ../../src/bashlib/x.sh
. ../../src/bashlib/xe.sh
. ../../src/bashlib/xj.sh

if ! command -v gobolt >/dev/null 2>&1 ; then
    echo "SKIP: gobolt not found"
    exit 0
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/qq_gobolt_xj.XXXXXX") || {
    echo "SKIP: cannot create temporary directory"
    exit 0
}
trap 'rm -rf "$WORK_DIR"' EXIT

_test_fail ()
{
    printf 'FAIL at test line %s\n' "${BASH_LINENO[0]}" >&2
    log_test 0 1
    return 1
}

test_case_gobolt_version ()
{
    local ver
    ver=$(gobolt json -m v 2>/dev/null) || { _test_fail; return 1; }

    if [[ "$ver" == *"gjson version: "*"1.20.6"* &&
          "$ver" == *"sjson version: "*"1.2.11"* &&
          "$ver" == *"pretty version: "*"1.3.0"* ]] ; then
        log_test 1 1
    else
        _test_fail
    fi
}

test_case_gobolt_quote_delete ()
{
    # sjson #100: 删除以转义双引号开头的 key 不能产生非法 JSON，
    # 也不能静默删除前一个兄弟 key。
    local quote_key='"'
    local quote_prefix='"1'
    local file1="$WORK_DIR/q1.json"
    local file2="$WORK_DIR/q2.json"
    local file3="$WORK_DIR/q3.json"
    local out

    printf '%s' '{"\"":1}' > "$file1"
    gobolt json -m d -k file -i "$file1" -p "$quote_key" || { _test_fail; return 1; }
    out=$(gobolt json -m r -t txt -k file -i "$file1" 2>/dev/null)
    if [[ "$out" == '{}' ]] ; then
        log_test 1 1
    else
        _test_fail
    fi

    printf '%s' '{"before":0,"\"":1}' > "$file2"
    gobolt json -m d -k file -i "$file2" -p "$quote_key" || { _test_fail; return 1; }
    gobolt json -m r -t type -k file -i "$file2" -p before >/dev/null 2>&1
    if (( $? == 4 )) ; then
        log_test 1 2
    else
        _test_fail
    fi

    out=$(gobolt json -m r -t txt -k file -i "$file2" 2>/dev/null)
    if [[ "$out" != *'\"'* && "$out" == *before* ]] ; then
        log_test 1 3
    else
        _test_fail
    fi

    printf '%s' '{"\"1":2}' > "$file3"
    gobolt json -m d -k file -i "$file3" -p "$quote_prefix" || { _test_fail; return 1; }
    out=$(gobolt json -m r -t txt -k file -i "$file3" 2>/dev/null)
    if [[ "$out" == '{}' ]] ; then
        log_test 1 4
    else
        _test_fail
    fi
}

test_case_xj_quote_roundtrip ()
{
    local -A tree=()
    local -A tree2=()
    local json_out

    x_from_json tree '{"\"":1,"before":0}' || { _test_fail; return 1; }
    x_to_json tree || { _test_fail; return 1; }
    json_out=$REPLY

    x_from_json tree2 "$json_out" || { _test_fail; return 1; }
    if x_equals tree tree2 ; then
        log_test 1 1
    else
        _test_fail
    fi
}

test_case_xj_complex_roundtrip ()
{
    local json='
    {
      "before": 0,
      "\"": 1,
      "nested": {
        "arr": [null, true, false, 3.14, {}, []],
        "obj": {"x": 1, "deep": {"z": null}},
        "empty_obj": {},
        "empty_arr": []
      }
    }'
    local -A tree=()
    local -A tree2=()
    local json_out

    x_from_json tree "$json" || { _test_fail; return 1; }
    x_to_json tree || { _test_fail; return 1; }
    json_out=$REPLY
    x_from_json tree2 "$json_out" || { _test_fail; return 1; }

    if ! x_equals tree tree2 ; then
        _test_fail
        return 1
    fi
    log_test 1 1

    x_get_leaf tree "{nested}$X{arr}$X[0]$X" || { _test_fail; return 1; }
    [[ "$REPLY" == "$X_VALUE_NULL" ]] || { _test_fail; return 1; }
    x_get_leaf tree "{nested}$X{arr}$X[1]$X" || { _test_fail; return 1; }
    [[ "$REPLY" == "$X_VALUE_TRUE" ]] || { _test_fail; return 1; }
    x_get_leaf tree "{nested}$X{arr}$X[2]$X" || { _test_fail; return 1; }
    [[ "$REPLY" == "$X_VALUE_FALSE" ]] || { _test_fail; return 1; }
    x_get_leaf tree "{nested}$X{arr}$X[3]$X" || { _test_fail; return 1; }
    [[ "$REPLY" == "3.14$X" ]] || { _test_fail; return 1; }
    x_get_leaf tree "{nested}$X{obj}$X{deep}$X{z}$X" || { _test_fail; return 1; }
    [[ "$REPLY" == "$X_VALUE_NULL" ]] || { _test_fail; return 1; }
    log_test 1 2

    x_get_node_type tree "{nested}$X{arr}$X[4]$X" path
    (( $? == X_NODE_KIND_OBJ_EMPTY )) || { _test_fail; return 1; }
    x_get_node_type tree "{nested}$X{arr}$X[5]$X" path
    (( $? == X_NODE_KIND_ARR_EMPTY )) || { _test_fail; return 1; }
    x_get_node_type tree "{nested}$X{empty_obj}$X" path
    (( $? == X_NODE_KIND_OBJ_EMPTY )) || { _test_fail; return 1; }
    x_get_node_type tree "{nested}$X{empty_arr}$X" path
    (( $? == X_NODE_KIND_ARR_EMPTY )) || { _test_fail; return 1; }
    log_test 1 3
}

test_case_gobolt_complex_quote_delete ()
{
    local file="$WORK_DIR/complex.json"
    local out
    local -A tree=()

    printf '%s' '{
      "before": 0,
      "\"": 1,
      "nested": {
        "arr": [null, true, false, 3.14, {}, []],
        "obj": {"x": 1, "deep": {"z": null}},
        "empty_obj": {},
        "empty_arr": []
      }
    }' > "$file"

    gobolt json -m d -k file -i "$file" -p '"' || { _test_fail; return 1; }
    out=$(gobolt json -m r -t txt -k file -i "$file" 2>/dev/null)
    x_from_json tree "$out" || { _test_fail; return 1; }

    x_get_leaf tree "{before}$X" || { _test_fail; return 1; }
    [[ "$REPLY" == "0$X" ]] || { _test_fail; return 1; }
    x_get_leaf tree "{nested}$X{arr}$X[1]$X" || { _test_fail; return 1; }
    [[ "$REPLY" == "$X_VALUE_TRUE" ]] || { _test_fail; return 1; }
    x_get_node_type tree "{nested}$X{arr}$X[4]$X" path
    (( $? == X_NODE_KIND_OBJ_EMPTY )) || { _test_fail; return 1; }
    x_get_node_type tree "{nested}$X{arr}$X[5]$X" path
    (( $? == X_NODE_KIND_ARR_EMPTY )) || { _test_fail; return 1; }
    x_get_leaf tree '{"}$X' >/dev/null 2>&1 && { _test_fail; return 1; }

    log_test 1 1
}

eval -- "$(AS_RUN_TEST_CASES)"

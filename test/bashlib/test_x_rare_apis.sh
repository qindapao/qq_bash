#!/usr/bin/env bash
. ../../src/bashlib/x.sh
. ../../src/bashlib/xj.sh
. ../../src/bashlib/xe.sh

FAILS=0
check () {
    local label=$1 want=$2 got=$3
    if [[ "$want" == "$got" ]] ; then
        printf '  ok   %-38s %s\n' "$label" "$got"
    else
        printf '  FAIL %-38s want=%q got=%q\n' "$label" "$want" "$got"
        FAILS=$((FAILS + 1))
    fi
}

# pop/shift leaf
x_init "$X_TYPE_OBJ"
declare -gA "T=($REPLY)"
x_insert T "{arr}$X[0]$X" a
x_insert T "{arr}$X[1]$X" b
x_pop_leaf T "{arr}$X" || { echo 'FAIL pop_leaf rc' ; exit 1 ; }
check 'pop_leaf value' 'b' "$REPLY"
x_get_leaf T "{arr}$X[0]$X"
check 'pop_leaf removed last' 'a' "$REPLY"
x_shift_leaf T "{arr}$X" || { echo 'FAIL shift_leaf rc' ; exit 1 ; }
check 'shift_leaf value' 'a' "$REPLY"
x_shift_leaf T "{arr}$X" >/dev/null 2>&1
check 'empty array shift fails' '1' "$(( $? != 0 ))"

# pop tree
x_init "$X_TYPE_OBJ"
declare -gA "U=($REPLY)"
x_insert U "{arr}$X[0]$X{k}$X" v
x_pop_tree U "{arr}$X" || { echo 'FAIL pop_tree rc' ; exit 1 ; }
x_get_node_type U "{arr}$X" path
check 'pop_tree leaves empty array' "$X_NODE_KIND_ARR_EMPTY" "$?"

# layer flat
x_init "$X_TYPE_OBJ"
declare -gA "V=($REPLY)"
x_insert V "{obj}$X{a}$X" 1
x_insert V "{obj}$X{b}$X" 2
x_layer_get_flat obj V "{obj}$X"
check 'layer_get_flat obj rc' '0' "$?"
check 'layer_get_flat obj has a' '1' "$([[ "$REPLY" == *a* ]] && echo 1 || echo 0)"
x_insert V "{arr}$X[0]$X" x
x_insert V "{arr}$X[1]$X" y
x_layer_get_flat arr V "{arr}$X"
check 'layer_get_flat arr rc' '0' "$?"

# pop flat assoc / shift flat array
x_init "$X_TYPE_OBJ"
declare -gA "W=($REPLY)"
x_insert W "{arr}$X[0]$X{k}$X" v
x_pop_to_flat_assoc W "{arr}$X" || { echo 'FAIL pop_flat_assoc rc' ; exit 1 ; }
check 'pop_flat_assoc has k' '1' "$([[ "$REPLY" == *k* ]] && echo 1 || echo 0)"
x_init "$X_TYPE_OBJ"
declare -gA "X2=($REPLY)"
x_insert X2 "{arr}$X[0]$X[0]$X" z
x_shift_to_flat_array X2 "{arr}$X" || { echo 'FAIL shift_flat_array rc' ; exit 1 ; }
check 'shift_flat_array has z' '1' "$([[ "$REPLY" == *z* ]] && echo 1 || echo 0)"

# push_leaf_fast
x_init "$X_TYPE_OBJ"
declare -gA "Y=($REPLY)"
x_insert Y "{arr}$X" "$X_VALUE_NULL_ARR"
x_push_leaf_fast Y "" "{arr}$X" a b || { echo 'FAIL push_leaf_fast rc' ; exit 1 ; }
x_get_leaf Y "{arr}$X[0]$X"
check 'push_leaf_fast first' 'a' "$REPLY"
x_get_leaf Y "{arr}$X[1]$X"
check 'push_leaf_fast second' 'b' "$REPLY"

# arg limits
x_get_arg_limits 3 || { echo 'FAIL get_arg_limits rc' ; exit 1 ; }
declare -A "LIMITS=($REPLY)"
check 'arg_limits MAX_ARG_STRLEN > 0' '1' "$(( LIMITS[MAX_ARG_STRLEN] > 0 ))"
check 'arg_limits AVAILABLE > 0' '1' "$(( LIMITS[AVAILABLE] > 0 ))"

if (( FAILS )) ; then
    printf '%d assertion(s) failed\n' "$FAILS"
    exit 1
fi
echo 'PASS: rare array/layer APIs'

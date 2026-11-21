#!/usr/bin/env bash
#
# dataclass: four lightweight container kinds + unified pool.

. ../../src/bashlib/data.sh

FAILS=0
check () {
    local label=$1 want=$2 got=$3
    if [[ "$want" == "$got" ]] ; then
        printf '  ok   %-38s %s\n' "$label" "$got"
    else
        printf '  FAIL %-38s want=%s got=%s\n' "$label" "$want" "$got"
        FAILS=$((FAILS + 1))
    fi
}

# ARR
xo_data_born_arr || { echo 'FAIL: born ARR' ; exit 1 ; }
check 'ARR handle' 'ARR_1' "$REPLY"
check 'ARR type' 'ARR' "$(xo_data_type ARR_1 ; printf %s "$REPLY")"
xo_data_is_live ARR_1 || { echo 'FAIL: ARR not live' ; exit 1 ; }
declare -n _arr=ARR_1
_arr=('a' 'b')
check 'ARR value' 'a,b' "$(printf '%s,' "${_arr[@]}" | sed 's/,$//')"

# ASSOC
xo_data_born_assoc || { echo 'FAIL: born ASSOC' ; exit 1 ; }
check 'ASSOC handle' 'ASSOC_2' "$REPLY"
declare -n _assoc=ASSOC_2
_assoc[hp]=7
_assoc[name]='hero'
check 'ASSOC value' '7' "${_assoc[hp]}"
check 'ASSOC type' 'ASSOC' "$(xo_data_type ASSOC_2 ; printf %s "$REPLY")"

# DTREE
xo_data_born_dtree || { echo 'FAIL: born DTREE' ; exit 1 ; }
check 'DTREE handle' 'DTREE_3' "$REPLY"
x_insert DTREE_3 "{a}$X" 'one' || { echo 'FAIL: DTREE insert' ; exit 1 ; }
check 'DTREE value' 'one' "${DTREE_3[{a}$X]}"

# ATREE
xo_data_born_atree || { echo 'FAIL: born ATREE' ; exit 1 ; }
check 'ATREE handle' 'ATREE_4' "$REPLY"
x_insert ATREE_4 "[0]$X" 'zero' || { echo 'FAIL: ATREE insert' ; exit 1 ; }
x_get_leaf ATREE_4 "[0]$X"
check 'ATREE value' 'zero' "$REPLY"

# bury
xo_data_bury ARR_1 || { echo 'FAIL: bury ARR' ; exit 1 ; }
if xo_data_is_live ARR_1 ; then echo 'FAIL: ARR still live' ; exit 1 ; fi
xo_data_bury ASSOC_2 || { echo 'FAIL: bury ASSOC' ; exit 1 ; }
xo_data_bury DTREE_3 || { echo 'FAIL: bury DTREE' ; exit 1 ; }
xo_data_bury ATREE_4 || { echo 'FAIL: bury ATREE' ; exit 1 ; }

# clear
xo_data_born_arr >/dev/null || { echo 'FAIL: born clear' ; exit 1 ; }
xo_data_clear
check 'pool empty after clear' '0' "${#XO_DATA_CLASS_POOL[@]}"
if xo_data_is_live ARR_5 ; then echo 'FAIL: ARR_5 still live' ; exit 1 ; fi

if (( FAILS )) ; then
    printf '%d assertion(s) failed\n' "$FAILS"
    exit 1
fi
echo 'PASS: dataclass containers'

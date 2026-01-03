((_VAR_IMPORTED++)) && return 0

# var_ as a reserved prefix

# Convert the parameter list into a set
var_params_to_set ()
{
    local -A var_set=()
    local var_head=$1
    shift
    while (($#)) ; do
        var_set["$var_head$1"]=1 ; shift
    done
    REPLY="${var_set[*]@K}"
}

# var_bitmap_unpack <bitmap> <var:bit> <var:bit> ...
# ---------------------------------------------------
# This function is used to decompose a bitmap into multiple Boolean variables.
#
# Usage examples:
#   var_bitmap_unpack "$bitmap" a:0 b:3 c:7
#
# Effect:
#   a = (bitmap >> 0) & 1
#   b = (bitmap >> 3) & 1
#   c = (bitmap >> 7) & 1
#
# Parameter description:
#   - The first parameter is bitmap
#   - Each subsequent parameter is "variable name: bit"
#
# Implementation principle (black magic analysis):
#   1. set -- "${@:2}" "$1"
#      Append bitmap to the last position in the parameter list.
#      In this way `${!#}` always points to the bitmap itself.
#
#   2. while (($#>1))
#      The loop processes all "var:bit" parameters, except the last parameter (bitmap).
#
#   3. ${1%:*}
#      Extract the variable name (remove the :bit part)
#      For example "foo:3" -> "foo"
#
#   4. ${1#*:}
#      Extract the bit (remove the variable name part)
#      For example "foo:3" -> "3"
#
#   5. printf -v "$var" '%d' $(( (bitmap >> bit) & 1 ))
#      Calculate whether the corresponding bit is 1 and assign it to the variable.
#
# Advantages of this function:
#   - No need to maintain two arrays (variable name array + bit array)
#   - There will be no misalignment of variable names and bit bits.
#   - Extremely scalable, just add "var:bit"
#   - Fully automated, suitable for scenarios with a large number of bitmap bits
#
# Notice:
#   This is Bash advanced black magic. If you are not familiar with it, you will
#       doubt your life after watching it for the first time.
#   But the logic is completely safe, controllable, and maintainable.
#
# More complex example:
# trie_bitmap_unpack "$tr_iter_bitmap" \
#     tr_is_iter_token:0 \
#     tr_is_iter_type:1 \
#     tr_is_iter_full_key:2 \
#     tr_is_iter_value:3 \
#     tr_is_iter_node:4 \
#     tr_is_iter_parent:5 \
#     tr_is_iter_children:6 \
#     tr_is_iter_cnt:7
var_bitmap_unpack ()
{
    set -- "${@:2}" "$1"
    while (($#>1)) ; do
        printf -v "${1%:*}" '%d' $(( (${!#} >> ${1#*:}) & 1 ))
        shift
    done
}

var_is_associative_array () { [[ "${!1@a}" == *A* ]] ; }

return 0


((_META_IMPORTED++)) && return 0

. "${BASH_SOURCE[0]%/*}/trie.sh"

# Hooking method and SUPER.
#
# Although aliases can be used to define methods in a more object-oriented style
# xx.func_name "$1" "$2"
# However, aliases have many pitfalls, and sometimes the expansion is unstable,
# so it is best to give up.
# alias ${obj_name}.cut_plus="cut_plus_my_class ${obj_name}"
# Unalias management of aliases is also very troublesome.
bless ()
{
    local tr_class=$1
    local tr_obj=$2
    local tr_obj_name=$3

    # CLASS Add the hook class name to the attribute
    local tr_class_chain
    tr_class_chain=${|trie_get_leaf "$tr_obj" "{CLASS}$S" 2>/dev/null;}
    tr_class_chain="${tr_class}${tr_class_chain:+ -> }${tr_class_chain}"

    trie_insert "$tr_obj" "{CLASS}$S" "$tr_class_chain"
    local tr_fn_name ; for tr_fn_name in ${ compgen -A function;} ; do
        case "$tr_fn_name" in
        new_${tr_class}|bless_${tr_class}|setup_${tr_class}) : ;;
        # FN: Last level method
        #SUPER: The parent tr_class method corresponding to each subclass method
        *_${tr_class})
            local tr_key=${tr_fn_name%"_$tr_class"}
            local tr_super=${|trie_get_leaf "$tr_obj" "{FN}$S{$tr_key}$S" 2>/dev/null;}

            trie_insert "$tr_obj" "{FN}$S{$tr_key}$S" "$tr_fn_name $tr_obj_name"
            trie_insert "$tr_obj" "{SUPER}$S{$tr_fn_name}$S" "${tr_super:-:}"
            ;;
        esac
    done
}

# After taking out the small object from the large object, the variable name of
# the small object needs to be re-bound.
# $1: The name of the new object
rebind_self ()
{
    local -n tr_self=$1
    local tr_new_name=$1
    local tr_phy_token tr_value

    [[ "${tr_self[{SELF}$S]}" != "$tr_new_name" ]] && {
        tr_self[{SELF}$S]=$tr_new_name
        # Trie tree atomic traversal, the class method cannot be called here
        # because the binding variable name is incorrect!
        local IFS=$'\n' ; local tr_top_lev tr_tuple
        local tr_iter=$'FN\nSUPER'
        for tr_top_lev in $tr_iter ; do
             for tr_tuple in ${|trie_iter "$tr_new_name" "{$tr_top_lev}$S" $((2#1001));} ; do
                eval -- set -- $tr_tuple ; tr_phy_token=$1 tr_value=$2
                [[ "$tr_value" == ':' ]] || {
                    tr_self[{$tr_top_lev}$S${tr_phy_token}$S]="${tr_value%' '*} $tr_new_name"
                }
            done
        done
    }
}

die ()
{
    echo "[ERROR] $*" >&2
    echo "Call stack:" >&2
    local i
    for ((i=1; i<${#FUNCNAME[@]}; i++)); do
        echo "  $i: ${FUNCNAME[$i]}() at ${BASH_SOURCE[$i]}:${BASH_LINENO[$((i-1))]}" >&2
    done
}

return 0


